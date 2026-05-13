export CC=emcc
export CFLAGS=-O3

export BIN=wart.wasm
export BINWAT=wart.wat
export OUT=src
export SRC=example

export BUILD=zig build --summary all --color on

cleandocs:
	@rm -rf docs/book

docs: cleandocs
	mdbook build docs

b:
	${BUILD}
bz:
	zig build --color on --summary all

bwasi:
	zig build -Dtarget=wasm32-wasi --summary all --color on

bwasip1:
	zig build -Dtarget=wasm32-wasip1 --summary all --color on

cw:
	@rm -rf $(OUT)/$(BIN)
	@mkdir -p $(OUT)


bw: cw
	$(CC) -o $(OUT)/$(BIN) $(SRC)/main.c $(CFLAGS)

rw: bw
	wasmer $(OUT)/$(BIN)
	wasmtime $(OUT)/$(BIN)

r:
	wart


# Examples compilation and testing
examples: examples/simple.wasm examples/hello.wasm examples/math.wasm examples/fibonacci.wasm examples/array.wasm

examples/%.wasm: examples/%.c
	@mkdir -p examples
	@if command -v emcc >/dev/null 2>&1; then \
		echo "Compiling $< with emscripten..."; \
		emcc -o $@ $< -s WASI_SDK=1 -s EXPORTED_FUNCTIONS='["_main"]' -s EXPORTED_RUNTIME_METHODS='["ccall"]' -O2; \
	elif command -v clang >/dev/null 2>&1; then \
		echo "Compiling $< with clang..."; \
		clang --target=wasm32-wasi -O2 -o $@ $< -nostdlib -Wl,--no-entry -Wl,--export-all; \
	else \
		echo "Error: Neither emcc nor clang found. Please install Emscripten or Clang."; \
		echo "To install Emscripten: https://emscripten.org/docs/getting_started/downloads.html"; \
		exit 1; \
	fi

# Run individual examples
run-hello: examples/hello.wasm b
	./zig-out/bin/wart examples/hello.wasm

run-math: examples/math.wasm b
	./zig-out/bin/wart examples/math.wasm

run-fibonacci: examples/fibonacci.wasm b
	./zig-out/bin/wart examples/fibonacci.wasm

run-array: examples/array.wasm b
	./zig-out/bin/wart examples/array.wasm

# Test all examples
test: examples/simple.wasm b
	@echo "Testing wart binary help functionality..."
	@./zig-out/bin/wart --help
	@echo ""
	@echo "Testing wart binary with no arguments..."
	@./zig-out/bin/wart
	@echo ""
	@echo "Testing wart binary version..."
	@./zig-out/bin/wart --version
	@echo ""
	@echo "Testing WASM execution with simple.wasm..."
	@./zig-out/bin/wart examples/simple.wasm 2>/dev/null && echo "✓ simple.wasm executed successfully" || echo "✗ simple.wasm execution failed"

# Clean examples
clean-examples:
	rm -f examples/*.wasm

wasm2wat: b
	echo "$(wasm2wat $(OUT)/$(BIN))" >> $(OUT)/$(BINWAT)

all: b examples

# Build WAT workloads when wabt is present
.PHONY: wat-wasm
wat-wasm:
	@if command -v wat2wasm >/dev/null 2>&1; then \
		echo "Compiling WAT workloads..."; \
		cd examples && for f in *.wat; do \
			[ -f "$$f" ] && echo "  Compiling $$f..." && wat2wasm "$$f" -o "$${f%.wat}.wasm"; \
		done; \
	else \
		echo "wat2wasm not found; skipping WAT builds"; \
	fi

.PHONY: b r examples run-hello run-math run-fibonacci run-array test clean-examples
.PHONY: bench bench-full
bench: b wat-wasm
	bash bench/run.sh --profile core-universal

bench-full: b wat-wasm
	@echo "Running pinned benchmark profiles..."
	bash bench/run.sh --profile core-universal
	bash scripts/run-benchmarks.sh --profile preview1
