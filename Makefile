.DEFAULT_GOAL := format

.PHONY: format
format:
	swiftformat Sources
	swiftformat Examples/AirPlayScreenshotApp/AirPlayScreenshotApp
