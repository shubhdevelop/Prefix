package main

import (
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsnotify/fsnotify"
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

func loadConfig() (*Config, error) {
	filename := ".prefix.yaml"
	home, err := os.UserHomeDir()
	configFileName := filepath.Join(home, filename)
	if err != nil {
		log.Printf("could not get home directory: %v\n", err)
		return nil, err
	}

	file, err := os.Open(configFileName)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			log.Printf("File not found: %s\n", configFileName)
			log.Printf("Creating a new config file, add the dump and destinations")
			// Handle file not existing (e.g., create it, exit)
			newConfigFile, err := os.Create(configFileName)
			if err != nil {
				log.Fatalf("Error create new config file %e:", err)
				return nil, err
			}

			defer func() {
				closeErr := newConfigFile.Close()
				if err == nil {
					err = closeErr 
				}
			}()
		} else {
			// Handle other potential errors (e.g., permission denied)
			log.Fatalf("Error opening file: %v\n", err)
			return nil, err
		}
	}
	defer func() {
		closeErr := file.Close()
		if err == nil {
			err = closeErr // Capture close error if no other error occurred
		}
	}()

	log.Printf("File exists and opened successfully: %s\n", configFileName)

	data, err := os.ReadFile(configFileName)
	if err != nil {
		log.Printf("failed to read config file: %v", err)
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		log.Printf("failed to parse YAML: %v", err)
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
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		log.Printf("failed to create destination directory: %v", err)
		return fmt.Errorf("failed to create destination directory: %w", err)
	}

	if _, err := os.Stat(destPath); err == nil {
		log.Printf("destination file already exists: %s", destPath)
		log.Printf("destination file already exists: %s", destPath)
		return fmt.Errorf("destination file already exists: %s", destPath)
	}

	if err := os.Rename(sourcePath, destPath); err == nil {
		return nil
	}

	if err := copyFile(sourcePath, destPath); err != nil {
		log.Printf("failed to copy file: %v", err)
		return fmt.Errorf("failed to copy file: %w", err)
	}

	if err := os.Remove(sourcePath); err != nil {
		log.Printf("failed to remove source file: %v", err)
		return fmt.Errorf("failed to remove source file: %w", err)
	}

	return nil
}

func copyFile(sourcePath, destPath string) error {
	sourceFile, err := os.Open(sourcePath)
	if err != nil {
		log.Printf("failed to open source file: %v", err)
		return fmt.Errorf("failed to open source file: %w", err)
	}
	defer func() {
		closeErr := sourceFile.Close()
		if err == nil {
			log.Printf("failed to close source file: %v", err)
			err = closeErr
		}
	}()
	destFile, err := os.Create(destPath)
	if err != nil {
		log.Printf("failed to create destination file: %v", err)
		return fmt.Errorf("failed to create destination file: %w", err)
	}
	defer func() {
		closeErr := destFile.Close()
		if err == nil {
			log.Printf("failed to close destination file: %v", err)
			err = closeErr
		}
	}()

	if _, err := io.Copy(destFile, sourceFile); err != nil {
		return err
	}

	// Copy file permissions
	sourceInfo, err :=	 os.Stat(sourcePath)
	if err != nil {
		log.Printf("failed to stat source file: %v", err)
		return fmt.Errorf("failed to stat source file: %w", err)
	}
	return os.Chmod(destPath, sourceInfo.Mode())
}

func organizeFiles(config *Config) error {
	files, err := os.ReadDir(config.DumpDirectory)
	if err != nil {
		log.Printf("failed to read dump directory: %v", err)
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

var timer *time.Timer

func main() {
	logFile, err := os.OpenFile("app.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o666)
	if err != nil {
		log.Fatal(err)
	}

	defer logFile.Close()

	log.SetOutput(logFile)

	// 3. Optional: Customize the log format (Date, Time, File name).
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)

	// Now all log.Println calls go to app.log instead of the console.
	log.Println("This message is written to the log file.")
	config, err := loadConfig()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	if _, err := os.Stat(config.DumpDirectory); os.IsNotExist(err) {
		log.Fatalf("Dump directory does not exist: %s", config.DumpDirectory)
	}

	log.Printf("Dump directory: %s", config.DumpDirectory)
	log.Printf("Processing %d destination rules", len(config.Destinations))

	watcher, _ := fsnotify.NewWatcher()
	defer func() {
		closeErr := watcher.Close()
		if err == nil {
			err = closeErr // Capture close error if no other error occurred
		}
	}()

	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}

				log.Println(event)
				// DEBOUNCING LOGIC:
				if timer != nil {
					timer.Stop()
				}

				// AfterFunc runs in its own goroutine automatically.
				timer = time.AfterFunc(5*time.Second, func() {
					log.Println("Timer expired, organizing files...")
					// Note: organizeFiles must be a function call inside this closure
					err := organizeFiles(config)
					if err != nil {
						log.Println(err)
					}
				})

			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Println("Error:", err)
			}
		}
	}()

	err = watcher.Add(config.DumpDirectory)
	if err != nil {
		log.Println(err)
	}
	select {}
}
