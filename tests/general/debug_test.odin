package main

import "core"

main :: proc() {
    data := new(Data)
    defer free(data)
}

Data :: struct {}
