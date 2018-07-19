OB_OPTS=-j 2 #-verbose 5
OB=ocamlbuild -use-ocamlfind  $(OB_OPTS)
OUT=qocamlbrowser
INSTALL=install -m 755

.PHONY: all celan clean install uninstall

all:
	$(OB) src/moc_dataItem.c src/moc_controller.c src/moc_abstractModel.c src/moc_historyModel.c \
    src/qrc_resources.c src/libcppstubs.a src/program.native

celan: clean
clean:
	$(RM) -r _build *.native

#use make install PREFIX=`opam config var prefix` to install
install:
	$(INSTALL) _build/src/program.native $(PREFIX)/bin/$(OUT)

uninstall:
	$(RM) -r $(PREFIX)/bin/$(OUT)
