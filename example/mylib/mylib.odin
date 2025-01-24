package mylib
import "core:path/filepath"
dirname :: proc(path: cstring) -> string {
    return filepath.dir(string(path))
}
