# Comprehensive Odin Style Guide for RuiShin Project
version: 2.1.0  
last_updated: 2024-10-05

A complete reference for writing idiomatic, high-quality Odin code aligned with RuiShin's architecture, policies, and conventions.

---

## Table of Contents

1. [Naming Conventions](#naming-conventions)
2. [RuiShin Visibility System](#ruishin-visibility-system)
3. [Nil Safety and Pointer Handling](#nil-safety-and-pointer-handling)
4. [Memory Management](#memory-management)
5. [Error Handling](#error-handling)
6. [Unions and Tagged Unions](#unions-and-tagged-unions)
7. [Type Definitions](#type-definitions)
8. [Procedures](#procedures)
9. [Control Flow](#control-flow)
10. [Context System](#context-system)
11. [Packages and Imports](#packages-and-imports)
12. [Comments and Documentation](#comments-and-documentation)
13. [Platform-Specific Code](#platform-specific-code)
14. [C Interop](#c-interop)
15. [Common Patterns](#common-patterns)
16. [Performance Considerations](#performance-considerations)
17. [Testing](#testing)
18. [Code Organization](#code-organization)
19. [Data-Oriented Design](#data-oriented-design)
20. [Parametric Polymorphism (Generics)](#parametric-polymorphism-generics)
21. [Advanced Language Features](#advanced-language-features)
22. [Logging System](#logging-system)
23. [Build System Integration](#build-system-integration)
24. [Advanced Patterns](#advanced-patterns)

---

## Naming Conventions

### Types

Use **PascalCase** for all type names:

```odin
// ✅ GOOD
User :: struct { ... }
FileHandle :: struct { ... }
ProcessResult :: enum { ... }
Vector3 :: [3]f32

// ❌ BAD
user :: struct { ... }           // Wrong case
file_handle :: struct { ... }    // Wrong case
process_Result :: struct { ... } // Inconsistent
```

---

## RuiShin Visibility System

**IMPORTANT**: RuiShin uses a **custom naming convention** different from standard Odin to provide web-like API familiarity for our target audience.

### Three-Tier Visibility System

#### 🔒 Private (File-Internal Only)

Use **`_snake_case`** + **`@(private)`** for procedures that are strictly file-internal:

```odin
// ✅ GOOD - Private functions (file-only access)
@(private)
_resolve_vertex_color :: proc(px, py: f32, paint: renderer.Paint) -> [4]f32 { ... }

@(private)
_stroke_raw :: proc(points: [][2]f32, stroke: renderer.Stroke) { ... }

@(private)
_validate_cache_coherency :: proc(cache: ^Cache) -> bool { ... }

// ❌ BAD
@(private)
processUserData :: proc(user: ^User) { ... }  // Wrong case
_process_user_data :: proc(user: ^User) { ... }  // Missing @(private)
```

**When to use private:**
- Implementation details that should never be used outside the file
- Helper functions for complex algorithms
- Internal state management
- Functions that might change frequently

#### 🏠 Internal (Package-Level Access)

Use **`snake_case`** for procedures that are internal to a package but might need to be accessed by other files in the same package:

```odin
// ✅ GOOD - Package/subsystem internal APIs
process_internal_data :: proc(data: []byte) -> Result { ... }
calculate_physics_step :: proc(entities: []Entity, dt: f32) { ... }
render_internal_buffer :: proc(buffer: ^Buffer) { ... }

// ❌ BAD
_process_internal_data :: proc(data: []byte) { ... }  // underscore (should be private)
ProcessInternalData :: proc(data: []byte) { ... }  // PascalCase (wrong)
processInternalData :: proc(data: []byte) { ... }  // camelCase (should be public)
```

**When to use internal:**
- Functions used by multiple files in the same package
- Internal APIs that might need to be overridden or extended
- Functions that are stable but not part of the public API
- Layer 2 implementations in RuiShin architecture

#### 🌍 Public API (Official External Interface)

Use **`camelCase`** for public procedures that are part of the official API:

```odin
// ✅ GOOD - Public API functions (web-like naming)
processUserData :: proc(user: ^User) -> Result { ... }
calculatePhysicsStep :: proc(entities: []Entity, dt: f32) { ... }
renderBuffer :: proc(buffer: ^Buffer) { ... }

// Layer 4 UI examples (from RuiShin architecture)
createButton :: proc(label: string, callback: proc()) -> ^Button { ... }
setWindowTitle :: proc(window: ^Window, title: string) { ... }

// ❌ BAD
process_user_data :: proc(user: ^User) { ... }  // snake_case (internal)
_process_user_data :: proc(user: ^User) { ... }  // underscore (private)
```

**When to use public API:**
- Official external interface
- Documented and stable functions
- Functions that are part of the package's contract
- Layer 3 and Layer 4 APIs in RuiShin architecture

### Type Definitions

All type definitions use **PascalCase**, regardless of visibility:

```odin
// ✅ GOOD - Types always use PascalCase
UserData :: struct { ... }
InternalCache :: struct { ... }
RenderBuffer :: struct { ... }

// Private types should still use @(private)
@(private)
InternalState :: struct { ... }

// ❌ BAD - Wrong case for types
user_data :: struct { ... }           // Wrong case
User_data :: struct { ... }           // Inconsistent
```

### Visibility Decision Guide

| Aspect | Private (`_snake_case`) | Internal (`snake_case`) | Public (`camelCase`) |
|--------|------------------------|--------------------------|----------------------|
| **Scope** | Single file only | Same package | External packages |
| **Attribute** | `@(private)` required | No attribute | No attribute |
| **Stability** | Can change anytime | Somewhat stable | Very stable |
| **Documentation** | None needed | Internal docs | Full documentation |
| **Usage** | Implementation details | Layer 2 implementations | Layer 3/4 APIs |
| **Example** | `_calculate_hash` | `process_physics` | `renderScene` |
| **RuiShin Layer** | Internal helpers | Layer 2 | Layers 3 & 4 |

### Variables

Use **snake_case** for variable names:

```odin
// ✅ GOOD
user_count := 10
file_path := "data/config.txt"
position_x: f32 = 0.0

// ❌ BAD
UserCount := 10           // PascalCase
filePath := "data.txt"    // camelCase
PositionX: f32 = 0.0      // PascalCase
```

### Constants

Use **SCREAMING_SNAKE_CASE** for constants:

```odin
// ✅ GOOD
MAX_BUFFER_SIZE :: 1024
DEFAULT_TIMEOUT :: 30
PI :: 3.14159265359

// ❌ BAD
max_buffer_size :: 1024   // Wrong case
MaxBufferSize :: 1024     // Wrong case
defaultTimeout :: 30      // Wrong case
```

### Acronyms

Keep acronyms uppercase in PascalCase, lowercase in snake_case:

```odin
// ✅ GOOD - Types
HTTPServer :: struct { ... }
URLParser :: struct { ... }
XMLDocument :: struct { ... }

// ✅ GOOD - Internal procedures
parse_http_request :: proc() { ... }
create_url_parser :: proc() { ... }
load_xml_file :: proc() { ... }

// ✅ GOOD - Public procedures (camelCase)
parseHTTPRequest :: proc() { ... }
createURLParser :: proc() { ... }
loadXMLFile :: proc() { ... }

// ❌ BAD
HttpServer :: struct { ... }    // Inconsistent
parse_HTTP_request :: proc()    // Wrong in snake_case
```

### Boolean Names

Use positive, descriptive names. Avoid negatives:

```odin
// ✅ GOOD
is_valid: bool
has_permission: bool
can_execute: bool
should_retry: bool

// ❌ BAD
not_invalid: bool        // Double negative
lacks_permission: bool   // Negative
cannot_execute: bool     // Negative (use can_execute)
```

---

## Nil Safety and Pointer Handling

Odin does not have compile-time null safety. You are responsible for checking pointers before dereferencing.

### Pointers: An Introduction

Sometimes you need your code to directly modify the value of a variable that lives somewhere else. You can do that using what's known as a pointer.

A pointer is a reference. It is used to "point out" something else in memory. Internally it contains the memory address of that "something else".

### A procedure that modifies an integer

Say that we have an integer variable and we want to make a procedure that can directly add 1 to that variable for us. We can do that using a procedure that accepts a pointer to an integer. Such a procedure can then use that pointer to directly modify the value of the integer. It will go to the memory address that the pointer contains and add 1 to the number it finds there. Here's how you can write that:

```odin
increment_number :: proc(num: ^int) {
    num^ += 1
}

number := 7
number_pointer := &number
increment_number(number_pointer)
fmt.println(number) // 8
```

`number := 7` creates a variable `number` of type `int` that contains 7. Note the `&` on the next line:

```odin
number_pointer := &number
```

The `&` fetches the memory address of `number`. This means that the variable `number_pointer` now contains that address. This address tells us where in the computer's memory `number` is stored. We can use that address to access and modify `number` from other parts of our code.

You don't need a separate variable `number_pointer`, you could just have written `increment_number(&number)`.

The type of `number_pointer` is `^int`. Any type that contains a `^` is a pointer. `^int` can be read as "pointer to integer", meaning that we expect this pointer to contain a memory address, and at that address in memory we expect to find an integer.

The procedure `increment_number` has a single parameter: `num: ^int`. That's the same type as `number_pointer`. So when we run `increment_number` and feed it `number_pointer`, then its parameter `num` contains the address of the variable `number`.

Inside `increment_number` we see this:

```odin
increment_number :: proc(num: ^int) {
    num^ += 1
}
```

The line `num^ += 1` fetches the integer at the address that `num` points to, adds 1 to it and stores it back at that address. That line is equivalent to writing:

```odin
num^ = num^ + 1
```

Above we see that `num^` can be used for two different things:

- `num^ = some_value` writes the value on the right side of the `=` into that which `num` points to.
- `num^ + 1` reads the value that `num` points to and adds 1 to it.

`num^ += 1` is the same as writing `*num += 1` in C. Note that the `^` is after the pointer name instead of before it.

Compare the position of the `^` in these two lines:

```odin
increment_number :: proc(num: ^int) {
```

and

```odin
num^ = num^ + 1
```

- In the first case it is to the left of type name. This is how you denote a pointer type.
- In the second case it is to the right of a pointer variable's name. This is how you read or write through a pointer.

Whenever the `^` appears on the right side, we call it the dereference operator. A pointer is essentially a reference to something, meaning that it contains information about where to find something. So to dereference it means to fetch the thing it references.

Note how I use the word "through" in "read or write through a pointer". This is a good way to talk about pointers: You are trying to read or write something, but you must use the address inside the pointer to get there, which is like "going through the pointer".

### nil: the zero value of a pointer

If you create a new variable of pointer type, like this:

```odin
my_pointer: ^int
```

then you are declaring a pointer to an integer, without giving it a value. As usual it will be initialized to zero. But what does zero mean for a pointer? What does the zero value of a memory address represent?

Internally a pointer is just a numerical value, comparable to an unsigned integer. On most 64 bit platforms, pointers can be seen as 64 bit unsigned integers. Or a 32 bit unsigned integer on most 32 bit platforms. This is because that's the biggest address that such a computer can reason about.

The biggest value a 64 bit unsigned integer can contain is `18446744073709551616`.

But that doesn't mean your computer can have that much memory. Currently, most CPU architectures only use 48 of those 64 bits. There are some architectures that use 52 bits.

48 bits still gives a memory limit of just over 256 terabytes (256000 gigabytes)! Your OS and computer's motherboard probably also has some limitations. So I would be surprised if it is possible to install much more than 100-1000 GB of memory (RAM) in your computer.

So there's nothing magical about pointers. A pointer of value zero can just be seen as the number zero. This zero value means "no address", meaning that the pointer is currently not referring to anything at all. There's a special keyword in Odin to denote pointers of value zero: `nil`.

Trying to read or write through a nil pointer will crash your program. The code below would crash, since it tries to write 10 through a nil pointer:

```odin
my_pointer: ^int
my_pointer^ = 10
```

Similarly, a procedure that reads or writes through a pointer parameter will crash if you feed nil into that parameter. In our earlier `increment_number` procedure, we can protect against such crashes by checking if the parameter `num` is not nil before trying to use it:

```odin
increment_number :: proc(num: ^int) {
    if num != nil {
        num^ += 1
    }
}
```

You can also use `==` instead of `!=` and instead do an early return:

```odin
increment_number :: proc(num: ^int) {
    if num == nil {
        return
    }

    num^ += 1
}
```

`nil` is the same as `nullptr` in C++ or `NULL` in older versions of C.

`nil` comes from the Latin word `nihil`. `null` comes from the Latin word `nullus`. Their meaning is similar, but `nihil` means "nothingness" while `nullus` means "nothing".

As you can see, `nil` and `nihil` is slightly more mystical and cool.

These examples, where we increment integers using a pointer, aren't all that useful since you'd probably just return a new number instead of bothering with a pointer. In the next section we'll look at modifying a struct through a pointer, which is a lot more useful.

### A pointer to a struct

In this example we'll use a procedure in order to modify a struct. We'll feed a pointer to a struct into the procedure. The procedure will modify a field of the struct through the pointer.

Here's a struct that describes a cat. It contains its name, age and color:

```odin
Cat :: struct {
    name: string,
    age: int,
    color: Cat_Color,
}

Cat_Color :: enum {
    Black,
    White,
    Orange,
    Tabby,
    Calico,
}
```

Below we create a new cat called "Patches". It's Patches' birthday, so we need to increment its age and print a happy message. In this example, `process_cat_birthday` takes a pointer to a `Cat` struct and increments the age field.

```odin
process_cat_birthday :: proc(cat: ^Cat) {
    if cat == nil {
        return
    }

    cat.age += 1
}

my_cat := Cat {
    name = "Patches",
    age = 7,
    color = .Calico,
}

process_cat_birthday(&my_cat)

// Hooray, Patches is now 8 years old!
fmt.printfln("Hooray, %v is now %v years old!", my_cat.name, my_cat.age)
```

Output of running this program is:

```
Hooray, Patches is now 8 years old!
```

Just like previously we fetch the address of a variable using the `&`:

```odin
process_cat_birthday(&my_cat)
```

The result of `&my_cat` is a value of type `^Cat`. It's a pointer to a struct of type `Cat`.

As before, the pointer just contains an address. At that address we find the memory that the variable `my_cat` uses to store its data. How much memory does this `my_cat` variable use? It uses 32 bytes because that's the combined size of the fields of the struct `Cat`.

Within `process_cat_birthday` we increment the age field by writing through the pointer:

```odin
cat.age += 1
```

Note where the line that prints "Hooray, Patches is now 8 years old!" is: It's after we've called `process_cat_birthday`. This is an important point to understand: By passing `my_cat` by pointer, we let `process_cat_birthday` modify the variable `my_cat` directly. In the code that follows the line `process_cat_birthday(&my_cat)`, we can see the changes that `process_cat_birthday` did to `my_cat`.

Unlike the examples in the previous section, we didn't have to write

```odin
cat^.age += 1
```

When you have a pointer to a struct, and access a field of the struct through that pointer, then the `^` is implicit. `cat^.age` and `cat.age` do the exact same thing.

In C++ or C `(*cat).age` and `cat->age` are identical. The Odin compiler knows that `cat` is a pointer, and uses that knowledge make `.` do the same thing as `->` does in C.

On the other hand, if you want to replace the the whole struct, then you need to use `^`. Below we have a procedure called `replace_cat` that replaces all the data that its `cat: ^Cat` parameter points to. Note how it uses `cat^ = {}`.

```odin
replace_cat :: proc(cat: ^Cat) {
    if cat == nil {
        return
    }

    cat^ = {
        name = "Klucke",
        age = 6,
        color = .Tabby,
    }
}
```

You can't just do `cat = {}` without the `^`. This is because assigning to a pointer means changing the address the pointer contains. In other words, assigning to a pointer means re-directing what the pointer refers to. But we want to go through the pointer and modify the memory it points to. So we have to use `cat^ = {}`.

### Copying a pointer and the address of a pointer

As I've mentioned throughout this chapter, you can think of a pointer as just containing a number. That number is an address that points to a location in memory. In this section we'll discuss what happens when you have two pointers containing the same address. The things we discuss here are meant to give you an intuition for what a pointer really is.

In the code below we have an integer variable `number`. We fetch the address of `number` and put it in `pointer1`. We then create another variable called `pointer2`, which is a copy of the variable `pointer1`. We then write the number 10 through `pointer2`.

```odin
number := 7
pointer1 := &number
pointer2 := pointer1
pointer2^ = 10
```

You can think of `pointer1` and `pointer2` as two variables containing the exact same number: They both contain the same memory address. To modify the original variable `number` you can go via any of the two pointers: `pointer1^ = 10` and `pointer2^ = 10` would both set the variable `number` to 10, because they both go through the same address.

Let's think a bit about what `pointer1` and `pointer2` actually are. They are two separate variables. This means that they must both store a separate copy of `number`'s address somewhere. If you fetched the address of `pointer1` and `pointer2` and printed it, then you would see two different addresses:

```odin
fmt.println(&pointer1)
fmt.println(&pointer2)
```

Note the `&` in front of both. The type of `&pointer1` and `&pointer2` is in this case `^^int`, which you can read as "pointer to a pointer to an integer". The above would print something like:

```
0x445C6FF868
0x445C6FF860
```

Pointers are by default printed using hexadecimal notation. If you rather look at "normal" numbers, then you can change the print lines to:

```odin
fmt.printfln("%i", &pointer1)
```

Note that the first one ends with 8 and the second one ends with 0. The exact numbers will not be the same on your computer. But it will be two different addresses. This shows that pointers are variables just like any other: `pointer1` and `pointer2` have separate locations in memory for storing whatever they contain. In this case they both store a separate copy of the same memory address. At the address that they both store, you find the value of the integer variable `number`.

### Under the hood: Addressables

We've seen how pointers can be used to get and set the value that the pointer refers to:

```odin
// Read a value through a pointer
read_value := some_pointer^

// Write a value through a pointer
some_pointer^ = 10
```

When `^` appears to the right of a pointer's name, we call it the dereference operator. But what is it that `^` actually does? As we'll see, there's more going on here than just reading and writing through the pointer.

Some of the things we talk about here aren't strictly necessary to know. But it may prove useful, interesting and demystifying. Here's an example of something we'll be able to understand at the end of this section:

How can the following code get a pointer that refers to the tenth element of array?

```odin
array: [20]int
element_pointer := &array[10]
```

After all, doesn't `array[10]` fetch something of type `int`? If you think about it, the above kind-of looks like it does the same as this:

```odin
array: [20]int
element := array[10]
element_pointer := &element
```

In which case `element_pointer` would not point to the tenth element of `array`. Instead, it would point to `element`, which is a copy of the tenth element. But that's not what happens when you do `&array[10]`. Somehow `&array[10]` gives you a pointer directly to the tenth element of the array. This section is all about understanding how.

When learning to program in C, I used to be scared of writing `&array[10]`. I thought that it would take the address of a copy of `array[10]`, instead of the giving me the address of the tenth element. I often did `array + 10` in C, because that felt more like it didn't use any "in-between copy". However, `&array[10]` works perfectly fine in both C and Odin.

Let's take a step back and look at some simple examples that will give us new insights and thereafter return to the array example.

Say that we again have an integer variable `number` and a pointer to that variable:

```odin
number: int
number_pointer := &number
```

We can now assign to `number` through `number_pointer` like this:

```odin
number_pointer^ = 10
```

The above seems to work like this: Whenever we find `number_pointer^` on the left side of an `=`, then it goes through the pointer and sets the value at that address.

We can also fetch the value of `number` through `number_pointer` like this:

```odin
another_number := number_pointer^
```

Similarly, the above seems to work like this: Whenever we find `number_pointer^` to the right of `:=` (or to the right of `=`), then that fetches the number the pointer refers to.

I put emphasis on "seems" above, because this is a surface-level explanation. It's an explanation that suffices in most cases.

But if we talk about what the compiler is actually doing internally, then we say that `number_pointer^` (the whole thing including the `^`) creates what is known as an addressable. As the name suggests, addressables are things that are possible to locate in memory. Addressables can be read, fetching their value. They can also be assigned to, writing their value.

Addressables are known as L-values in C. L-value is short for "Left-value". Historically L-values could only appear on the left side of an assignment, which is no longer true. Nowadays it just means that they can appear on the left side, meaning that it is possible to assign to them.

To reduce the confusion, some people re-brand L-value to instead mean "Locator-value", because it can locate the data when you assign to it. That sounds about equally confusing to me.

Some skip all of this and just say "addressable" instead.

So on a line like

```odin
number_pointer^ = 10
```

Then we write into the addressable `number_pointer^` because it is on the left side of the assignment. But on a line like

```odin
another_number := number_pointer^
```

then the addressable `number_pointer^` is read because it is on the right side of the assignment. Here `another_number` is actually also an addressable: It's something we can assign to.

I want to repeat and stress something here: To the compiler, `number_pointer^`, including the `^`, creates an addressable. An addressable is an internal thing that the compiler can use to read and write into some part of memory. I like to think of addressables as the compiler's own internal version of pointers. Meaning that when we write `number_pointer^`, then the compiler still retains the address of whatever `number_pointer` points to, so you can assign to it.

There are things that are not addressables, because they cannot be assigned to. A constant number like 7 is an example. You can never assign to it, because doing:

```odin
7 = some_variable
```

doesn't make any sense.

In C we call these non-addressables R-values, because they can only appear on the right side in an assignment.

Let's return to the initial example; creating a pointer to a value you've just fetched from an array:

```odin
array: [20]int
element_pointer := &array[10]
```

If you have an array and fetch the element at index 10 using `array[10]`, then you might think that you've already completely lost the original memory address of that value. After all, the result of doing `element := array[10]` is something of type `int`.

But in the example above `element_pointer` somehow contains the direct address to the tenth element in the array. This is because `array[10]` is an addressable that refers to the tenth element of the array. Taking the address of an addressable, like `&array[10]` does, gives you this "original address".

As a final example, if you write `some_pointer^` and immediately take the address of it again, then you get the original pointer back:

```odin
number := 7
number_pointer := &number
number_pointer_again := &number_pointer^
// Both these pointers refer to `number`!
```

Again, one could have thought that `number_pointer^` gives you some in-between value and that the pointer `number_pointer_again` would refer to that in-between value. But no, `number_pointer^` is an addressable, and taking the address of an addressable gives back the original memory address. As long as the addressable's value hasn't crossed over the `=`, then you still have one last chance to fetch its original address.

### Always Validate Pointers at Boundaries

```odin
// ✅ GOOD - Check at function boundaries
processDrawing :: proc(drawing: ^rsd.Drawing) -> bool {
    if drawing == nil {
        return false
    }
    
    // Safe to use drawing now
    render_internal(drawing)
    return true
}

// ❌ BAD - No nil check
processDrawing :: proc(drawing: ^rsd.Drawing) -> bool {
    render_internal(drawing)  // CRASH if nil!
    return true
}
```

### Use Comma-Ok Pattern for Nullable Returns

```odin
// ✅ GOOD - Return both value and validity
loadAsset :: proc(path: string) -> (asset: ^Asset, ok: bool) {
    data := os.read_entire_file(path) or_return
    defer delete(data)
    
    asset = parse_asset(data)
    if asset == nil {
        return nil, false
    }
    
    return asset, true
}

// Usage
asset, ok := loadAsset("sprites/player.png")
if !ok {
    // Handle error
}
// asset is guaranteed non-nil here

// ❌ BAD - Only return pointer
loadAsset :: proc(path: string) -> ^Asset {
    // Caller doesn't know if nil is error or valid
    return parse_asset(data)
}
```

### Document Ownership and Lifetime

```odin
// ✅ GOOD - Clear ownership documentation
// createTexture allocates a new texture. Caller owns the result.
// Must call destroyTexture when done.
createTexture :: proc(width, height: int) -> ^Texture {
    texture := new(Texture)
    // ... initialize
    return texture
}

destroyTexture :: proc(texture: ^Texture) {
    if texture == nil do return
    free(texture)
}
```

### Use `or_return` for Early Validation

```odin
// ✅ GOOD - Clean early returns
loadAndProcessFile :: proc(path: string) -> (result: ProcessedData, ok: bool) {
    data := os.read_entire_file(path) or_return
    defer delete(data)
    
    parsed := parse_data(data) or_return
    validated := validate(parsed) or_return
    
    return process(validated), true
}

// ❌ BAD - Nested if statements
loadAndProcessFile :: proc(path: string) -> (result: ProcessedData, ok: bool) {
    data, data_ok := os.read_entire_file(path)
    if !data_ok {
        return {}, false
    }
    defer delete(data)
    
    parsed, parse_ok := parse_data(data)
    if !parse_ok {
        return {}, false
    }
    
    // ... more nesting
}
```

### Never Return Pointers to Stack Data

```odin
// ❌ BAD - Returns pointer to stack variable
getBadPointer :: proc() -> ^int {
    value := 42
    return &value  // WRONG! Stack variable will be destroyed
}

// ✅ GOOD - Allocate on heap
getGoodPointer :: proc() -> ^int {
    value := new(int)
    value^ = 42
    return value  // Safe - allocated on heap
}

// ✅ BETTER - Return value directly
getValue :: proc() -> int {
    return 42  // Best - no allocation needed
}
```

---

## Memory Management

### Always Use Context Allocators

Never use raw `malloc`/`free`:

```odin
// ✅ GOOD - Using context allocator
data := make([]int, 100)
defer delete(data)

// ✅ GOOD - Using temp allocator
data := make([]int, 100, context.temp_allocator)
defer free_all(context.temp_allocator)

// ❌ BAD - Never use C-style allocation
import "core:c"
data := cast(^int)c.malloc(100 * size_of(int))  // NO!
defer c.free(data)                               // NO!
```

### Temporary Allocations

Use `context.temp_allocator` for short-lived data:

```odin
// ✅ GOOD - Temporary string building
buildMessage :: proc(name: string, age: int) -> string {
    return fmt.aprintf("User: %s, Age: %d", name, age, 
                       allocator = context.temp_allocator)
}

main :: proc() {
    defer free_all(context.temp_allocator)
    
    msg := buildMessage("Alice", 30)
    fmt.println(msg)
    // msg will be freed at end of main
}

// ❌ BAD - Memory leak
buildMessage :: proc(name: string, age: int) -> string {
    return fmt.aprintf("User: %s, Age: %d", name, age)
    // Caller must remember to delete, easy to forget!
}
```

### Always Pair Allocations with Cleanup

Use `defer` immediately after allocation:

```odin
// ✅ GOOD - Immediate defer
processFile :: proc(path: string) {
    data := make([]byte, 1024)
    defer delete(data)
    
    // ... use data
}

// ❌ BAD - defer far from allocation
processFile :: proc(path: string) {
    data := make([]byte, 1024)
    
    // 50 lines of code...
    
    defer delete(data)  // Easy to miss, hard to verify
}
```

### Pre-Allocate Known Sizes

```odin
// ✅ GOOD - Pre-allocate with reserve
items := make([dynamic]Item, 0, 1000)  // Reserve space for 1000
defer delete(items)

for i in 0..<1000 {
    append(&items, Item{...})  // No reallocation
}

// ❌ BAD - Repeated reallocations
items := make([dynamic]Item)
defer delete(items)

for i in 0..<1000 {
    append(&items, Item{...})  // May reallocate many times
}
```

---

## Error Handling

### Comma-Ok Pattern for Simple Failures

```odin
// ✅ GOOD - Boolean ok for simple success/fail
parseNumber :: proc(s: string) -> (value: int, ok: bool) {
    // Try to parse
    for c in s {
        if c < '0' || c > '9' {
            return 0, false
        }
    }
    return parse_int(s), true
}

// Usage
value, ok := parseNumber("123")
if !ok {
    log.error("Failed to parse")
    return
}
```

### Error Enums for Multiple Failure Modes

```odin
// ✅ GOOD - Enum for different error types
ParseError :: enum {
    None,
    FileNotFound,
    InvalidFormat,
    OutOfMemory,
}

parseConfig :: proc(path: string) -> (config: Config, err: ParseError) {
    data := os.read_entire_file(path) or_return {}, .FileNotFound
    defer delete(data)
    
    config = parse_json(data) or_return {}, .InvalidFormat
    return config, .None
}

// Usage
config, err := parseConfig("settings.json")
switch err {
case .None:
    // Success
case .FileNotFound:
    log.error("Config file not found")
case .InvalidFormat:
    log.error("Invalid JSON format")
case .OutOfMemory:
    log.error("Out of memory")
}
```

### Never Use Magic Numbers or Error Codes

```odin
// ❌ BAD - Magic numbers
processData :: proc(data: []byte) -> int {
    if len(data) == 0 {
        return -1  // What does -1 mean?
    }
    if !validate(data) {
        return -2  // What does -2 mean?
    }
    return 0  // Success?
}

// ✅ GOOD - Explicit error enum
ProcessError :: enum {
    None,
    EmptyData,
    ValidationFailed,
}

processData :: proc(data: []byte) -> ProcessError {
    if len(data) == 0 {
        return .EmptyData
    }
    if !validate(data) {
        return .ValidationFailed
    }
    return .None
}
```

### Always Propagate Errors

```odin
// ✅ GOOD - Propagate errors up the call stack
loadAndProcess :: proc(path: string) -> (result: Data, ok: bool) {
    raw_data := loadRawData(path) or_return
    processed := processData(raw_data) or_return
    validated := validate(processed) or_return
    return validated, true
}

// ❌ BAD - Silently ignore errors
loadAndProcess :: proc(path: string) -> Data {
    raw_data, ok := loadRawData(path)
    // Ignoring ok!
    
    processed, ok2 := processData(raw_data)
    // Ignoring ok2!
    
    return processed  // May return garbage data
}
```

### Error Propagation Patterns

Effective error propagation is crucial for maintainable code:

```odin
// ✅ GOOD - Basic error propagation
processFile :: proc(path: string) -> (Result, Error) {
    file, err := openFile(path)
    if err != .None {
        return {}, err  // Propagate error
    }
    defer closeFile(file)
    
    data, err := readFile(file)
    if err != .None {
        return {}, err  // Propagate error
    }
    defer delete(data)
    
    result, err := parseData(data)
    if err != .None {
        return {}, err  // Propagate error
    }
    
    return result, .None  // Success
}

// ✅ GOOD - Using or_return for cleaner propagation
processFileClean :: proc(path: string) -> (Result, Error) {
    file, err := openFile(path) or_return
    defer closeFile(file)
    
    data, err := readFile(file) or_return
    defer delete(data)
    
    result, err := parseData(data) or_return
    
    return result, .None
}

// ✅ GOOD - Error wrapping for context
processFileWithContext :: proc(path: string) -> (Result, Error) {
    file, err := openFile(path)
    if err != .None {
        return {}, .FileOpenError{path: path, cause: err}
    }
    defer closeFile(file)
    
    data, err := readFile(file)
    if err != .None {
        return {}, .FileReadError{path: path, cause: err}
    }
    defer delete(data)
    
    result, err := parseData(data)
    if err != .None {
        return {}, .ParseError{path: path, cause: err}
    }
    
    return result, .None
}
```

### Error Propagation Best Practices

```odin
// ✅ GOOD - Early return pattern
validateAndProcess :: proc(data: []byte) -> (Result, Error) {
    // Validate early
    if len(data) == 0 {
        return {}, .EmptyData
    }
    
    if data[0] != MAGIC_BYTE {
        return {}, .InvalidFormat
    }
    
    // Process with confidence
    result, err := parseData(data)
    if err != .None {
        return {}, err
    }
    
    return result, .None
}

// ✅ GOOD - Error accumulation pattern
processMultipleFiles :: proc(paths: []string) -> ([]Result, []Error) {
    results := make([]Result, 0, len(paths))
    errors := make([]Error, 0, len(paths))
    
    for path in paths {
        result, err := processFile(path)
        if err != .None {
            errors.append(err)
            continue
        }
        results.append(result)
    }
    
    return results, errors
}

// ✅ GOOD - Partial success pattern
processWithFallback :: proc(primaryPath, fallbackPath: string) -> Result {
    result, err := processFile(primaryPath)
    if err == .None {
        return result
    }
    
    // Log primary failure but continue
    logError("Primary file failed:", err)
    
    result, err := processFile(fallbackPath)
    if err != .None {
        logError("Fallback file also failed:", err)
        return defaultResult()
    }
    
    return result
}
```

### Common Error Propagation Anti-Patterns

```odin
// ❌ BAD - Ignoring errors (silent failure)
processFileBad :: proc(path: string) -> Result {
    file, _ := openFile(path)  // Ignoring error!
    defer closeFile(file)
    
    data, _ := readFile(file)  // Ignoring error!
    defer delete(data)
    
    result, _ := parseData(data)  // Ignoring error!
    
    return result  // Might be invalid!
}

// ❌ BAD - Using panic for normal errors
processFilePanic :: proc(path: string) -> Result {
    file, err := openFile(path)
    if err != .None {
        panic("Failed to open file!")  // Never panic for expected errors!
    }
    // ...
}

// ❌ BAD - Returning error codes instead of proper errors
processFileCodes :: proc(path: string) -> int {
    file, err := openFile(path)
    if err != .None {
        return -1  // Magic error code!
    }
    // What if -1 is a valid result?
}

// ❌ BAD - Inconsistent error handling
processFileInconsistent :: proc(path: string) -> (Result, Error) {
    file, err := openFile(path)
    if err != .None {
        return {}, err
    }
    defer closeFile(file)
    
    data, ok := readFile(file)  // Using bool instead of Error!
    if !ok {
        return {}, .FileReadError  // Inconsistent!
    }
    defer delete(data)
    
    // ...
}
```

### Error Propagation Checklist

1. **Always check errors** - Never ignore error returns
2. **Propagate errors appropriately** - Use `or_return` for cleaner code
3. **Add context when wrapping errors** - Help with debugging
4. **Use early returns** - Reduce nesting and improve readability
5. **Consider partial success** - Sometimes continue with fallback
6. **Be consistent** - Use the same error type throughout a module
7. **Document error conditions** - Help callers understand what can go wrong
8. **Avoid panics for expected errors** - Only panic for truly exceptional conditions

---

## Unions and Tagged Unions

### Basic Union Definition

Unions in Odin **do not use field names**. List types directly:

```odin
// ✅ GOOD - Direct type list
Asset_Parse_Result :: union {
    ^g2d.SVG_Element,
    ^rsd.Drawing,
    string,  // error message
}

// ❌ BAD - Field names (this is wrong!)
Asset_Parse_Result :: union {
    svg_element: ^g2d.SVG_Element,  // NO!
    rsd_drawing: ^rsd.Drawing,      // NO!
    error: string,                   // NO!
}
```

### Switch on Unions with `in`

Use the `in` keyword to switch on union types:

```odin
// ✅ GOOD - Use `in` for union switching
result: Asset_Parse_Result

switch v in result {
case ^g2d.SVG_Element:
    fmt.println("Got SVG element:", v)
    render_svg(v)
    
case ^rsd.Drawing:
    fmt.println("Got RSD drawing:", v)
    render_rsd(v)
    
case string:
    log.error("Parse failed:", v)
}

// ❌ BAD - Missing `in` keyword
switch result {  // WRONG! Won't compile
case ^g2d.SVG_Element:
    // ...
}
```

### Type Checking Without Switching

```odin
// Check if union holds a specific type
if svg, ok := result.(^g2d.SVG_Element); ok {
    fmt.println("It's an SVG:", svg)
}

// Or just check the type
if _, ok := result.(^g2d.SVG_Element); ok {
    fmt.println("It's an SVG")
}
```

### Maybe Pattern for Optional Values

```odin
// ✅ GOOD - Union for optional return
Maybe_User :: union {
    ^User,
    // nil state is implicit
}

findUser :: proc(id: int) -> Maybe_User {
    user := lookup(id)
    if user == nil {
        return nil  // Returns empty union
    }
    return user
}

// Usage
result := findUser(123)
switch v in result {
case ^User:
    fmt.println("Found user:", v.name)
case:
    fmt.println("User not found")
}
```

---

## Type Definitions

### Struct Initialization

Use `=` for field assignment, not `:`:

```odin
// ✅ GOOD - Use equals sign
config := Asset_Manager_Config{
    max_assets          = 1024,
    max_memory_mb       = 512,
    enable_background_loading = true,
    cache_directory     = "artifacts/cache/",
}

// ❌ BAD - Using colons (WRONG!)
config := Asset_Manager_Config{
    max_assets:          1024,  // NO!
    max_memory_mb:       512,   // NO!
}
```

### Array Comparisons

Arrays cannot be compared directly with `!=` or `==`:

```odin
default_tint := [4]f32{1.0, 1.0, 1.0, 1.0}

// ✅ GOOD - Compare element-by-element
if config.tint_color[0] != 1.0 || 
   config.tint_color[1] != 1.0 || 
   config.tint_color[2] != 1.0 || 
   config.tint_color[3] != 1.0 {
    // Apply tint
}

// ✅ GOOD - Helper function
is_default_tint :: proc(tint: [4]f32) -> bool {
    return tint[0] == 1.0 && 
           tint[1] == 1.0 && 
           tint[2] == 1.0 && 
           tint[3] == 1.0
}

if !is_default_tint(config.tint_color) {
    // Apply tint
}

// ❌ BAD - Direct comparison
if config.tint_color != [4]f32{1.0, 1.0, 1.0, 1.0} {  // Won't compile!
    // ...
}
```

### Distinct Types for Type Safety

```odin
// ✅ GOOD - Prevent accidental mixing of IDs
User_ID :: distinct int
Product_ID :: distinct int

user_id: User_ID = 123
product_id: Product_ID = 456

// product_id = user_id  // Compiler error!

// Must explicitly cast to mix
product_id = Product_ID(user_id)  // Explicit intent
```

---

## Procedures

### Multiple Return Values

Procedures that return 2 values must have both captured:

```odin
// Procedure returns 2 values
divide :: proc(a, b: int) -> (result: int, ok: bool) {
    if b == 0 {
        return 0, false
    }
    return a / b, true
}

// ✅ GOOD - Capture both values
result, ok := divide(10, 2)
if !ok {
    log.error("Division by zero")
    return
}

// ✅ GOOD - Ignore with underscore
result, _ := divide(10, 2)

// ❌ BAD - Only capturing one value
result := divide(10, 2)  // ERROR: expected 1 expression, got 2
```

### Named Return Values

```odin
// ✅ GOOD - Named returns for clarity
parseData :: proc(input: string) -> (result: Data, error_msg: string, ok: bool) {
    if len(input) == 0 {
        error_msg = "Empty input"
        ok = false
        return  // Returns zero values for result
    }
    
    result = parse(input)
    ok = true
    return
}
```

### Procedure Overloading

```odin
// ✅ GOOD - Explicit overloading for related operations
draw :: proc{draw_circle, draw_rectangle, draw_triangle}

draw_circle :: proc(x, y, radius: f32) { ... }
draw_rectangle :: proc(x, y, w, h: f32) { ... }
draw_triangle :: proc(p1, p2, p3: [2]f32) { ... }

// Usage - compiler picks the right one
draw(100, 100, 50)           // Calls draw_circle
draw(0, 0, 100, 200)         // Calls draw_rectangle
draw([2]f32{0,0}, [2]f32{10,10}, [2]f32{5,20})  // Calls draw_triangle
```

---

## Control Flow

### No Parentheses in If Conditions

```odin
// ✅ GOOD - No parentheses
if x > 10 {
    // ...
}

if user != nil && user.active {
    // ...
}

// ❌ BAD - Unnecessary parentheses
if (x > 10) {  // Don't do this
    // ...
}
```

### For Loops - Prefer Range-Based

```odin
items := []int{1, 2, 3, 4, 5}

// ✅ GOOD - Range-based iteration
for item in items {
    fmt.println(item)
}

// ✅ GOOD - With index
for item, index in items {
    fmt.println(index, item)
}

// ✅ GOOD - Pointer to modify
for &item in items {
    item *= 2
}

// ❌ BAD - C-style loop (only when necessary)
for i := 0; i < len(items); i += 1 {
    fmt.println(items[i])
}
```

### Switch Statements

```odin
// ✅ GOOD - No fallthrough, cleaner syntax
switch value {
case 1:
    do_something()
case 2, 3:  // Multiple cases
    do_something_else()
case 4..10:  // Range
    do_range_thing()
case:  // Default
    do_default()
}

// Inline switch for type detection
result := switch type in value {
case int:    type * 2
case string: len(type)
case:        0
}
```

---

## Context System

### Using Context Allocators

```odin
// ✅ GOOD - Temporary allocations
build_string :: proc() -> string {
    return fmt.aprintf("Result: %d", 42, 
                       allocator = context.temp_allocator)
}

main :: proc() {
    defer free_all(context.temp_allocator)
    
    s := build_string()
    fmt.println(s)
    // s is freed at end of main
}
```

### Custom Context for Scoped Changes

```odin
// ✅ GOOD - Override allocator for scope
process_with_arena :: proc() {
    arena: virtual.Arena
    virtual.arena_init_growing(&arena)
    defer virtual.arena_destroy(&arena)
    
    context.allocator = virtual.arena_allocator(&arena)
    
    // All allocations in this scope use arena
    data := make([]byte, 1000)
    // No need to delete - arena cleans up everything
}
```

---

## Platform-Specific Code

### Use `when` for Compile-Time Conditionals

The `when` statement is evaluated at **compile-time**, not runtime:

```odin
// ✅ GOOD - Platform-specific compilation
when ODIN_OS == .Windows {
    import "core:sys/windows"
    
    open_file :: proc(path: string) -> os.Handle {
        // Windows-specific implementation
        return windows_open(path)
    }
} else when ODIN_OS == .Darwin {
    import "core:sys/darwin"
    
    open_file :: proc(path: string) -> os.Handle {
        // macOS-specific implementation
        return darwin_open(path)
    }
} else when ODIN_OS == .Linux {
    open_file :: proc(path: string) -> os.Handle {
        // Linux-specific implementation
        return linux_open(path)
    }
}

// Usage remains the same across platforms
handle := open_file("data.txt")
```

### Debug vs Release Configuration

```odin
// ✅ GOOD - Conditional compilation
when DEBUG {
    log :: proc(msg: string) {
        fmt.println("[DEBUG]", msg)
    }
} else {
    log :: proc(msg: string) {
        // No-op in release
    }
}

// The compiler will completely remove the
// log function call in release builds
```

### Build Tags and Configuration

```odin
// Define custom build configurations
when #config(ENABLE_PROFILING, false) {
    start_profile :: proc() { ... }
    end_profile :: proc() { ... }
} else {
    start_profile :: proc() {}
    end_profile :: proc() {}
}

// Build with: odin build . -define:ENABLE_PROFILING=true
```

---

## Advanced Language Features

### Bit Sets for Flags

```odin
// ✅ GOOD - Type-safe flags
Permission :: enum {
    Read,
    Write,
    Execute,
}

Permissions :: bit_set[Permission; u8]

// Usage
user_perms: Permissions = {.Read, .Write}

if .Execute in user_perms {
    execute_file()
}

// Add permission
user_perms += {.Execute}

// Remove permission
user_perms -= {.Write}

// Check multiple
if {.Read, .Write} <= user_perms {
    // Has both read and write
}
```

### Using Statement for Field Promotion

```odin
// ✅ GOOD - Automatic field access
Vector3 :: struct {
    x, y, z: f32,
}

Entity :: struct {
    using position: Vector3,
    health: f32,
}

entity: Entity
entity.x = 10  // Can access directly without entity.position.x
entity.y = 20
entity.z = 30
entity.health = 100
```

### Swizzling for Vector Components

```odin
// ✅ GOOD - Swizzle components
v := [4]f32{1, 2, 3, 4}

xy := v.xy     // [2]f32{1, 2}
zw := v.zw     // [2]f32{3, 4}
rgb := v.rgb   // [3]f32{1, 2, 3}

// Also works with assignment
v.xy = [2]f32{10, 20}
// v is now {10, 20, 3, 4}
```

### SOA (Struct of Arrays) Layout

```odin
// ✅ GOOD - Automatic SOA layout
Entity :: struct {
    position: [3]f32,
    velocity: [3]f32,
    health: f32,
}

// #soa creates SOA layout automatically
entities: #soa[100]Entity

// Access still looks normal
entities[0].position = {1, 2, 3}
entities[0].velocity = {0.1, 0.2, 0.3}

// But internally stored as:
// positions[100], velocities[100], healths[100]
// for better cache performance
```

### Maps (Hash Tables)

```odin
// ✅ GOOD - Standard map usage
users := make(map[string]^User)
defer delete(users)

// Insert
users["alice"] = &alice_user

// Lookup with comma-ok
user, ok := users["alice"]
if ok {
    fmt.println("Found:", user.name)
}

// Delete
delete_key(&users, "alice")

// Iterate
for key, value in users {
    fmt.println(key, value)
}
```

### Matrix Types

```odin
// ✅ GOOD - Matrix operations
Mat4 :: matrix[4, 4]f32

identity := matrix[4, 4]f32{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
}

transform := identity
transform[0, 3] = 10  // Set translation X
```

### Transmute for Type Punning

```odin
// ✅ GOOD - Type punning (use carefully!)
float_bits := transmute(u32)f32(3.14)
fmt.printf("Float bits: 0x%08X\n", float_bits)

// Convert array to slice
fixed_array := [5]int{1, 2, 3, 4, 5}
slice := fixed_array[:]  // Safer than transmute

// ⚠️ WARNING - transmute bypasses type safety!
// Only use when you understand memory layout
```

### Generic Constraints with Where Clauses

```odin
import "core:intrinsics"

// ✅ GOOD - Constrained generics
add :: proc(a, b: $T) -> T 
    where intrinsics.type_is_numeric(T) 
{
    return a + b
}

// Can only be called with numeric types
result := add(5, 10)          // OK
// result := add("a", "b")    // Compiler error!

// Multiple constraints
clamp :: proc(val, min, max: $T) -> T 
    where intrinsics.type_is_numeric(T),
          intrinsics.type_is_comparable(T)
{
    if val < min do return min
    if val > max do return max
    return val
}
```

### Slicing and Subslicing

```odin
// ✅ GOOD - Slice operations
arr := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

sub := arr[2:5]     // [3, 4, 5]
start := arr[3:]    // [4, 5, 6, 7, 8, 9, 10]
end := arr[:4]      // [1, 2, 3, 4]

// Slices are views - they share memory
sub[0] = 999
// arr is now [1, 2, 999, 4, 5, 6, 7, 8, 9, 10]
```

---

## Logging System

### RuiShin Centralized Logging

**CRITICAL**: All logging must use the centralized `logging/logging.odin` system. Never use `fmt.printf` or similar for logging purposes.

### Logging Must Be Guarded by `when DEBUG`

```odin
import "logging"

// ✅ GOOD - Debug logging guarded by when
processData :: proc(data: []byte) {
    when DEBUG {
        logging.debug(.Renderer, fmt.tprintf("Processing %d bytes", len(data)))
    }
    
    // ... actual work
    
    when DEBUG {
        logging.debug(.Renderer, "Processing complete")
    }
}

// ❌ BAD - Direct fmt calls for logging
processData :: proc(data: []byte) {
    fmt.println("Processing", len(data))  // NO! Use logging system
}

// ❌ BAD - Unguarded debug logging
processData :: proc(data: []byte) {
    logging.debug(.Renderer, "Processing")  // NO! Missing when DEBUG guard
}
```

### Logging Levels

```odin
import "logging"

// Runtime logging (works in all builds if enabled)
logging.info(.Renderer, "Starting render")
logging.warn(.Memory, "Low memory warning")
logging.error(.IO, "Failed to load file")

// Debug-only logging (compile-time removed in release)
when DEBUG {
    logging.debug(.Shaping, fmt.tprintf("Shaped %d glyphs", count))
    logging.trace(.Atlas, "Cache lookup")
}
```

### Logging Configuration Profiles

```odin
import "logging"

main :: proc() {
    // Initialize with default configuration
    logging.init_default()
    defer logging.shutdown()
    
    when DEBUG {
        // Use predefined profile for text rendering
        logging.use_profile(.Text_Rendering)
        
        // Or configure custom subsystems
        logging.enable_subsystem(.Shaping, .TRACE)
        logging.enable_subsystem(.Fonts, .DEBUG)
    }
    
    // ... application code
}
```

### Log Files Location

Log files are written to `logs/` directory relative to the executable:

```odin
import "logging"

main :: proc() {
    // Initialize with file logging
    logging.init_with_file("logs/app.log")
    defer logging.shutdown()
    
    // All logging now goes to both console and file
}
```

### Frame-Based Logging

```odin
import "logging"

render_loop :: proc() {
    frame: u64 = 0
    
    for !should_quit() {
        logging.begin_frame(frame)
        defer logging.end_frame()
        
        // Frame rendering
        when DEBUG {
            logging.debug(.Renderer, fmt.tprintf("Frame %d", frame))
        }
        
        render_scene()
        frame += 1
    }
}
```

### Default Build Logging

Per RuiShin policy, **default builds** (`odin run build`) should have **minimal logging only**:

```odin
// Default release build - minimal logging
main :: proc() {
    logging.init()
    defer logging.shutdown()
    
    // Only lifecycle and errors in default builds
    logging.info(.Lifecycle, "Application started")
    
    // ... application code
    
    logging.info(.Lifecycle, "Application shutting down")
}
```

### Debug Build Logging

Debug builds enable full logging via `-define:DEBUG=true`:

```bash
# Debug build with full logging
odin run build -define:DEBUG=true

# Sets DEBUG flag which enables when DEBUG blocks
```

---

## Build System Integration

### Primary Build Command

Per RuiShin policy, the **primary build command** must always work:

```bash
# From project root
odin run build/build.odin -file

# From build directory
cd build && odin run build.odin -file
```

### Build Modes

```bash
# Default release build
odin run build/build.odin -file

# Debug build
BUILD_MODE=debug odin run build/build.odin -file

# Static build
STATIC_BUILD=true odin run build/build.odin -file

# Fully static build
STATIC_BUILD=true BUILD_MISSING_STATIC_LIBS=true odin run build/build.odin -file
```

### Build Validation

Before committing, always validate:

```bash
# Run build validation script
./scripts/build-check.sh

# Or manually test
odin run build/build.odin -file  # From root
cd build && odin run build.odin -file  # From build dir
```

---

## Testing

### Test Naming Convention

```odin
package my_package

import "core:testing"

@(test)
test_parse_valid_number :: proc(t: ^testing.T) {
    result, ok := parse_number("123")
    testing.expect(t, ok, "Should parse valid number")
    testing.expect_value(t, result, 123)
}

@(test)
test_parse_invalid_number :: proc(t: ^testing.T) {
    _, ok := parse_number("abc")
    testing.expect(t, !ok, "Should reject invalid number")
}
```

### Test Coverage Requirements

Per RuiShin policy:
- Unit tests: ≥80% coverage
- Integration tests: ≥70% coverage
- Overall: ≥75% coverage

### Testing API Functions

Create unit tests for all new API functions:

```odin
package render2d_tests

import "core:testing"
import "../render2d"

@(test)
test_create_button_public_api :: proc(t: ^testing.T) {
    // Test public API (camelCase)
    button := render2d.createButton("Click Me", nil)
    testing.expect(t, button.label == "Click Me")
    testing.expect(t, button.enabled == true)
}
```

---

## Code Organization

### RuiShin Project Structure

```
ruishin/
├── ols.json
├── artifacts/
├── build/
│   └── build.odin
├── src/
│   ├── main.odin
│   ├── engine/          # Layer 4 - High-level application
│   ├── ui/              # Layer 4 - Declarative UI
│   ├── render2d/        # Layer 3 - Public 2D API
│   ├── render3d/        # Layer 3 - Public 3D API
│   ├── render2d_impl/   # Layer 2 - Implementation
│   ├── audio/           # Layer 3 - Public audio API
│   ├── files/           # Layer 3 - Public file API
│   ├── logging/         # Centralized logging system
│   └── vfs/
├── logs/                # Log output directory
├── scripts/
├── tests/
└── vendor-local/        # Layer 1 - Never exposed
    ├── sokol-odin/
    ├── odin-freetype/
    └── odin-harfbuzz/
```

### Package Structure

```odin
// Each directory is a package
// entities/player.odin
package entities

Player :: struct { ... }

// entities/enemy.odin
package entities

Enemy :: struct { ... }

// Can share types within package
```

### Separation of Concerns

Per RuiShin architecture:

1. **Layer 4 (UI)**: High-level declarative APIs (`ui/`)
2. **Layer 3 (APIs)**: Public immediate-mode APIs (`render2d/`, `audio/`, etc.)
3. **Layer 2 (Impl)**: Backend implementations (`render2d_impl/`, `audio_impl/`)
4. **Layer 1 (Backends)**: Never exposed (`vendor-local/`)

---

## Data-Oriented Design

### Structure of Arrays (SoA) for Performance

```odin
// ✅ GOOD - Cache-friendly SoA
Entities :: struct {
    positions:  []Vector3,
    velocities: []Vector3,
    healths:    []f32,
    count:      int,
}

update_physics :: proc(entities: ^Entities, dt: f32) {
    // Cache-friendly: accesses contiguous memory
    for i in 0..<entities.count {
        entities.positions[i] += entities.velocities[i] * dt
    }
}

// ❌ BAD - AoS can be cache-unfriendly
Entity :: struct {
    position: Vector3,
    velocity: Vector3,
    health: f32,
}

update_physics :: proc(entities: []Entity, dt: f32) {
    // Potentially more cache misses
    for &entity in entities {
        entity.position += entity.velocity * dt
    }
}
```

### When to Use SoA

Use Structure of Arrays when:
- Processing large datasets (>1000 items)
- Performance is critical (game entities, particles)
- Working with SIMD operations
- Cache utilization matters

---

## Parametric Polymorphism (Generics)

### Generic Procedures

```odin
// Generic clamp procedure
clamp :: proc(val, min, max: $T) -> T {
    if val <= min do return min
    if val >= max do return max
    return val
}

// Usage with different types
int_val := clamp(50, 0, 100)           // T = int
float_val := clamp(3.14, 0.0, 10.0)    // T = f32
```

### Generic Structs

```odin
// Generic container
Container :: struct($T: typeid) {
    items: [dynamic]T,
    count: int,
}

// Usage
int_container: Container(int)
string_container: Container(string)
```

### Compile-Time Constants

```odin
// Procedure with compile-time constant parameter
create_array :: proc($N: int) -> [N]int {
    return [N]int{}
}

// Usage
arr := create_array(100)  // Creates [100]int
```

---

## Advanced Patterns

### Initialization and Shutdown

```odin
// @init and @fini attributes
@(init)
startup :: proc() {
    fmt.println("Program started")
}

@(fini)
shutdown :: proc() {
    fmt.println("Program ending")
}
```

### Defer for Cleanup

```odin
// ✅ GOOD - defer for guaranteed cleanup
processFile :: proc(path: string) {
    file := os.open(path, os.O_RDONLY)
    defer os.close(file)  // Always runs at end of scope
    
    data := make([]byte, 1024)
    defer delete(data)
    
    // ... work with file and data
    // Cleanup happens automatically in reverse order
}
```

### Virtual Table Pattern for Polymorphism

```odin
// ✅ GOOD - VTable pattern for polymorphic behavior
Node_VTable :: struct {
    render: proc(node: ^Node, ctx: rawptr),
    update: proc(node: ^Node, dt: f32),
    cleanup: proc(node: ^Node),
}

Node :: struct {
    vtable: ^Node_VTable,
    id: int,
}

Custom_Node :: struct {
    using base: Node,
    custom_data: string,
}

custom_vtable := Node_VTable{
    render = custom_render,
    update = custom_update,
    cleanup = custom_cleanup,
}

createCustomNode :: proc() -> ^Custom_Node {
    node := new(Custom_Node)
    node.vtable = &custom_vtable
    return node
}
```

---

## Summary Checklist

**Naming:**
- [ ] Types in PascalCase
- [ ] Public API procedures in camelCase (RuiShin convention)
- [ ] Internal procedures in snake_case
- [ ] Private procedures in _snake_case with @(private)
- [ ] Constants in SCREAMING_SNAKE_CASE
- [ ] Variables in snake_case

**Nil Safety:**
- [ ] Validate pointers at function boundaries
- [ ] Use comma-ok pattern for nullable returns
- [ ] Document ownership and lifetime expectations
- [ ] Use `or_return` for early validation
- [ ] Never return pointers to stack-allocated data

**Memory:**
- [ ] Use `context.allocator` or `context.temp_allocator`
- [ ] Pair allocations with `defer` immediately
- [ ] Never use raw `malloc`/`free`

**Errors:**
- [ ] Use comma-ok pattern for simple failures
- [ ] Use error enums for multiple failure modes
- [ ] Never return error codes or magic numbers
- [ ] Always check and propagate errors appropriately
- [ ] Use `or_return` for cleaner error propagation

**Logging:**
- [ ] All logging uses `logging/logging.odin` system
- [ ] Debug logging guarded by `when DEBUG`
- [ ] Log files written to `logs/` directory
- [ ] Default builds have minimal logging only
- [ ] Never use `fmt.printf` for logging

**Build System:**
- [ ] Primary command works: `odin run build/build.odin -file`
- [ ] Test from both project root and build directory
- [ ] All changes tested with build validation script

**Style:**
- [ ] No parentheses around if conditions
- [ ] Use `defer` for cleanup
- [ ] Prefer `for item in items` over C-style loops
- [ ] Use `when` for platform-specific code
- [ ] Document public APIs with examples

**Performance:**
- [ ] Avoid allocations in hot paths
- [ ] Consider SoA for large datasets (>1000 items)
- [ ] Pre-allocate buffers when possible
- [ ] Use `#soa` for automatic cache-friendly layout

**Architecture:**
- [ ] Follow RuiShin four-layer system
- [ ] Layer 1 (backends) never exposed
- [ ] Layer 2 (implementations) marked internal
- [ ] Layer 3 (APIs) public and stable
- [ ] Layer 4 (UI) provides high-level abstractions

**Advanced:**
- [ ] Use explicit overloading for related procedures
- [ ] Use parametric polymorphism for generic code
- [ ] Apply data-oriented design principles
- [ ] Manage allocators appropriately
- [ ] Use bit sets for type-safe flags
- [ ] Use `using` for field promotion where appropriate

---

**Version:** 2.1.0  
**Last Updated:** 2024-10-05  
**Project:** RuiShin UI Library

This style guide represents best practices for writing clean, idiomatic Odin code specifically for the RuiShin project, incorporating both fundamental and advanced concepts while aligning with project policies and architecture.
