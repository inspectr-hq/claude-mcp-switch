# Claude MCP Switch

Native macOS menu bar app for managing Claude Desktop MCP server entries.

## Current Stage

This repository has been reduced to a thin app skeleton:

- SwiftPM-backed macOS menu bar app with Xcode project support
- Minimal server manager window and settings window
- File-backed registry and Claude Desktop config sync services
- Small test suite covering settings, registry encoding, config preservation, and window helpers

## Not Included Yet

- Full CRUD server editor
- Advanced import conflict handling
- Backup browser and recovery UI
- Release packaging workflow

## Development

Run tests from `app/`:

```bash
swift test
```
