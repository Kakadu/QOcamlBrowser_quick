MOC=`qmake -query QT_INSTALL_BINS`/moc
CC=g++ -g -fPIC -std=c++0x `pkg-config --cflags Qt5Core` -I`ocamlfind query lablqml` -I`ocamlc -where` \
   -Dprotected=public -Dprivate=public
CLINK=g++ -g
CLINKLIBS=`pkg-config --libs Qt5Quick`
OUT=qocamlbrowser
GEN_CMX=DataItem.cmx AbstractModel.cmx Controller.cmx
MOC_CPP=$(addprefix moc_,$(GEN_CMX:.cmx=_c.cpp) )
GEN_CPP=$(GEN_CMX:.cmx=_c.o) $(MOC_CPP:.cpp=.o)
GEN_MOC=$(GEN_CMX:.cmx=_c.cpp)
OCAMLOPT=ocamlfind opt -package compiler-libs.common,unix -linkpkg -g

CMX=helpers.cmx tree.cmx S.cmx Richify.cmx program.cmx
#CMX_TEST=Test.cmx

.SUFFIXES: .cpp .h .o .ml .cmx .cmo .cmi
.PHONY: all depend clean

all: $(GEN_CMX) $(CMX)  library_code $(GEN_MOC) $(GEN_CPP) main.o
	$(CLINK) -L`ocamlc -where` -L`ocamlfind query lablqml` \
	 $(GEN_CPP) camlcode.o main.o -lasmrun -llablqml_stubs  `ocamlfind query lablqml`/lablqml.a \
	-lunix -lcamlstr $(CLINKLIBS) $(NATIVECCLIBS)  -o $(OUT)

depend:
	ocamlfind dep *.ml *.ml > .depend

library_code:
	$(OCAMLOPT) -output-obj -dstartup -I `ocamlfind query lablqml` lablqml.cmxa str.cmxa \
	$(GEN_CMX) $(CMX) -linkall -o camlcode.o

moc_%.cpp: %.h
	$(MOC) $< > $@

.cpp.o:
	$(CC) -c $< -I.

.ml.cmx:
	$(OCAMLOPT) -I `ocamlfind query lablqml` -c $<

clean:
	rm *.o *.cm[oiax] *.cmxa *.o.startup.s $(MOC_CPP) -f

QMLS=ApiBrowser.qml  PathEditor.qml  Root.qml  Scrollable.qml  ScrollBar.qml
install:
	cp $(OUT) $(PREFIX)/bin
	cp *.qml  $(PREFIX)/bin

uninstall:
	cd $(PREFIX)/bin && rm -fr $(OUT) $(QMLS)

-include  $(shell ocamlc -where)/Makefile.config
include .depend
