package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	DumpDirectory string        `yaml:"dump_directory"`
	Destinations  []Destination `yaml:"destinations"`
}

type Destination struct {
	Path   string `yaml:"path"`
	Prefix string `yaml:"prefix,omitempty"`
	Suffix string `yaml:"suffix,omitempty"`
}

func loadConfig(configPath string) (*Config, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse YAML: %w", err)
	}

	return &config, nil
}

func matchesPattern(filename string, dest Destination) bool {
	// when both prefix and suffix are specified, both must match
	if dest.Prefix != "" && dest.Suffix != "" {
		return strings.HasPrefix(filename, dest.Prefix) && strings.HasSuffix(filename, dest.Suffix)
	}
	if dest.Prefix != "" {
		return strings.HasPrefix(filename, dest.Prefix)
	}
	if dest.Suffix != "" {
		return strings.HasSuffix(filename, dest.Suffix)
	}
	return false
}

func moveFile(sourcePath, destPath string) error {
	// make sure destination directory exists
	destDir := filepath.Dir(destPath)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("failed to create destination directory: %w", err)
	}

	if _, err := os.Stat(destPath); err == nil {
		return fmt.Errorf("destination file already exists: %s", destPath)
	}

	if err := os.Rename(sourcePath, destPath); err == nil {
		return nil
	}

	if err := copyFile(sourcePath, destPath); err != nil {
		return fmt.Errorf("failed to copy file: %w", err)
	}

	if err := os.Remove(sourcePath); err != nil {
		return fmt.Errorf("failed to remove source file: %w", err)
	}

	return nil
}

func copyFile(sourcePath, destPath string) error {
	sourceFile, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, sourceFile); err != nil {
		return err
	}

	// Copy file permissions
	sourceInfo, err := os.Stat(sourcePath)
	if err != nil {
		return err
	}
	return os.Chmod(destPath, sourceInfo.Mode())
}

func organizeFiles(config *Config) error {
	files, err := os.ReadDir(config.DumpDirectory)
	if err != nil {
		return fmt.Errorf("failed to read dump directory: %w", err)
	}

	movedCount := 0
	skippedCount := 0

	for _, file := range files {
		if file.IsDir() {
			continue
		}

		filename := file.Name()
		sourcePath := filepath.Join(config.DumpDirectory, filename)
		moved := false

		for _, dest := range config.Destinations {
			if matchesPattern(filename, dest) {
				destPath := filepath.Join(dest.Path, filename)

				log.Printf("Moving: %s -> %s", sourcePath, destPath)

				if err := moveFile(sourcePath, destPath); err != nil {
					log.Printf("Error moving %s: %v", filename, err)
					skippedCount++
				} else {
					log.Printf("Success: %s", filename)
					movedCount++
					moved = true
				}
				break // Move to first matching destination only
			}
		}

		if !moved {
			log.Printf("No match found for: %s", filename)
			skippedCount++
		}
	}

	log.Printf("\nSummary: %d files moved, %d files skipped", movedCount, skippedCount)
	return nil
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: file-organizer <config.yaml>")
	}

	configPath := os.Args[1]

	log.Printf("Loading configuration from: %s", configPath)
	config, err := loadConfig(configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	if _, err := os.Stat(config.DumpDirectory); os.IsNotExist(err) {
		log.Fatalf("Dump directory does not exist: %s", config.DumpDirectory)
	}

	log.Printf("Dump directory: %s", config.DumpDirectory)
	log.Printf("Processing %d destination rules", len(config.Destinations))

	if err := organizeFiles(config); err != nil {
		log.Fatalf("Failed to organize files: %v", err)
	}

	log.Println("File organization completed!")
}
