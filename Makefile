
run: proj4
	./proj4

proj4: $(wildcard *.odin)
	odin build . -out:proj4 -o:speed

clean:
	rm proj4

