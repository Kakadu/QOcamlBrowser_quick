#include "stubs.h"

#include <QtGui/QGuiApplication>
//#include <QApplication>
#include <QtWidgets/QApplication>
#include <QtQuick/qquickview.h>
#include <QtQml/QQmlEngine>
#include <QtQml/QQmlComponent>
#include <QtQml/QQmlApplicationEngine>

void doCaml() {
  CAMLparam0();
  static value *closure = nullptr;
  if (closure == nullptr) {
    closure = caml_named_value("doCaml");
  }
  Q_ASSERT(closure!=nullptr);
  caml_callback(*closure, Val_unit); // should be a unit
  CAMLreturn0;
}

int main(int argc, char ** argv) {
    caml_main(argv);
    QApplication app(argc, argv);

    QQmlApplicationEngine engine;

    QQmlContext *ctxt = engine.rootContext();
    registerContext(QString("rootContext"), ctxt);
    doCaml();

    engine.load("Root.qml");
    QList<QObject*> xs = engine.rootObjects();
    if (xs.length() == 0) {
        qDebug() << "Can't load QML components. Exit.";
        return 1;
    }
    QQuickWindow *window = qobject_cast<QQuickWindow*>(xs.at(0));
    window->showMaximized(); 
    return app.exec();
}

