# NESE - An NES emulator

## How to use

```
nese [path-to-ines-file]
```

## Pre-built binaries

- Go to Action > Build and Upload Artifacts > Artifacts

## Things that worked

- CPU (No invalid op codes)
- PPU (Sprite and Background rendering)
- Control
- CHR Ram (even on mapper 0)

## Things that not worked

- iNes 2.0
- ~~Super mario brothers (IDK why)~~ (CMP set flags fault)
- ~~Tetris (BG not render while playing)~~ (forgot to implement single screen mirroring)
- Audio (I got no idea how audio work)

## Default Control

### Debug feature

| Button        | Feature                                              |
| ------------- | ---------------------------------------------------- |
| <kbd>F2</kbd> | Play & Pause the emulator                            |
| <kbd>F3</kbd> | Step frame                                           |
| <kbd>F4</kbd> | Print PPU debug info to console                      |
| <kbd>F5</kbd> | Enable logging (slow the emulator down dramatically) |

### Player 1

| Key    | Button            |
| ------ | ----------------- |
| A      | <kbd>Space</kbd>  |
| B      | <kbd>LShift</kbd> |
| Select | <kbd>LCtrl</kbd>  |
| Start  | <kbd>E</kbd>      |
| Up     | <kbd>W</kbd>      |
| Down   | <kbd>S</kbd>      |
| Left   | <kbd>A</kbd>      |
| Right  | <kbd>D</kbd>      |

### Player 2

| Key    | Button       |
| ------ | ------------ |
| A      | <kbd>J</kbd> |
| B      | <kbd>K</kbd> |
| Select | <kbd>L</kbd> |
| Start  | <kbd>/</kbd> |
| Up     | <kbd>↑</kbd> |
| Down   | <kbd>↓</kbd> |
| Left   | <kbd>→</kbd> |
| Right  | <kbd>←</kbd> |

## Currently supported mappers

- Mapper 0
- Mapper 1
- Mapper 2
- Mapper 3

## How to build

This project used zig 0.12.0

## References

- OLC NES: https://github.com/OneLoneCoder/olcNES
- NesDev wiki: https://www.nesdev.org
