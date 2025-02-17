lib.wasm: main.odin
	odin build . -target:freestanding_wasm32 -o:speed -out:bin/lib.wasm