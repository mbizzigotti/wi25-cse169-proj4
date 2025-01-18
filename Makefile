
run: proj4
	./proj4

proj4: main.odin
	odin build . -out:proj4

clean:
	rm proj4

