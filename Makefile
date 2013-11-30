MOC=`qmake -query QT_INSTALL_BINS`/moc
RCC=`qmake -query QT_INSTALL_BINS`/rcc
#DO_QML_DEBUG=-DQT_QML_DEBUG -DQT_DECLARATIVE_DEBUG -DQT_QUICK_LIB -DQT_QML_LIB -DQT_NETWORK_LIB -DQT_GUI_LIB -DQT_CORE_LIB
CC=g++ -g -fPIC -std=c++0x $(DO_QML_DEBUG) \
	`pkg-config --cflags Qt5Core Qt5Widgets Qt5Quick` -I`ocamlfind query lablqml` -I`ocamlc -where` \
	-Dprotected=public -Dprivate=public
CLINK=g++ -g
CLINKLIBS=`pkg-config --libs Qt5Quick Qt5Widgets`
OUT=qocamlbrowser
GEN_CMX=DataItem.cmx AbstractModel.cmx Controller.cmx HistoryModel.cmx
MOC_CPP=$(addprefix moc_,$(GEN_CMX:.cmx=_c.cpp) )
GEN_CPP=$(GEN_CMX:.cmx=_c.o) $(MOC_CPP:.cpp=.o)
GEN_MOC=$(GEN_CMX:.cmx=_c.cpp)
OCAMLOPT=ocamlfind opt -package compiler-libs.common,unix,threads -linkpkg -thread -g

CMX=helpers.cmx tree.cmx S.cmx Comb.cmx Richify.cmx HistoryZipper.cmx program.cmx

.SUFFIXES: .qrc .cpp .h .o .ml .cmx .cmo .cmi
.PHONY: all depend clean install uninstall

all: $(GEN_CMX) $(CMX)  library_code $(GEN_MOC) $(GEN_CPP) resources.qrc qrc_resources.cpp qrc_resources.o main.o
	$(CLINK) -L`ocamlc -where` -L`ocamlfind query lablqml` -L`ocamlfind query threads` \
	 $(GEN_CPP) camlcode.o qrc_resources.o main.o \
	-lthreads -lasmrun -llablqml_stubs `ocamlfind query lablqml`/lablqml.a \
	-lunix -lcamlstr $(CLINKLIBS) $(NATIVECCLIBS) -lpthread -o $(OUT)

depend:
	ocamlfind dep *.ml *.ml > .depend

library_code:
	$(OCAMLOPT) -output-obj -dstartup -I `ocamlfind query lablqml` lablqml.cmxa str.cmxa \
	$(GEN_CMX) $(CMX) -linkall -o camlcode.o

moc_%.cpp: %.h
	$(MOC) $< > $@

.cpp.o:
	$(CC) -c $< -I.

QMLS=ApiBrowser.qml  PathEditor.qml  Root.qml  Scrollable.qml  ScrollBar.qml
qrc_%.cpp: %.qrc $(QMLS)
	$(RCC) -name resources $< -o $@

.ml.cmx:
	$(OCAMLOPT) -I `ocamlfind query lablqml` -c $<

clean:
	rm *.o *.cm[oiatx] *.cmxa *.o.startup.s $(MOC_CPP) qrc_resources.* -f

install:
	cp $(OUT) $(PREFIX)/bin

uninstall:
	rm -fr $(PREFIX)/bin/$(OUT)

-include  $(shell ocamlc -where)/Makefile.config
include .depend
