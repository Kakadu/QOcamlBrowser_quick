OUT=qocamlbrowser
.PHONY: all clean install uninstall

all: 
	./build

clean:
	rm -fr _build

install:
	cp _build/src/program.native $(PREFIX)/bin/$(OUT)

uninstall:
	rm -fr $(PREFIX)/bin/$(OUT)

