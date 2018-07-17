import QtQuick 2.1
import QtQuick.Controls 1.0
import QtQuick.Layouts 1.0

ApplicationWindow {
    // next two properties regulate how big  text blocks and latters will be
    property int defaultFontSize: 19
    property int defaultTextFieldHeight: defaultFontSize + 4
    property string backgroundColor: "#FFFFDF"
    width: 800
    height: 600

/*
      menuBar: MenuBar {
        Menu {
            title: "File"
            //MenuItem { text: "Open..." }
            MenuItem {
                text: "Close"
                shortcut: "Ctrl-Q"
                onTriggered: { Qt.quit() }
            }
         }

            Menu {
            title: "Edit"
            MenuItem { text: "Cut" }
            MenuItem { text: "Copy" }
            MenuItem { text: "Paste" }
        }
    } */
    ExclusiveGroup {
        Action {
            id: api_browsing_action
            text: "Api Browsing"
            checkable: true
            Component.onCompleted: checked = true
            onTriggered: {
                root.applyPaths();
                root.state = "BROWSE_API";
            }
        }
        Action {
            id: path_editing_action
            text: "Path Editing"
            checkable: true
            Component.onCompleted: checked = false
            onTriggered: {
                root.setCurrentPaths();
                root.state = "EDIT_PATHS";
            }
        }
    }

    toolBar: ToolBar {
        RowLayout {
            Menu {
                id: backContextMenu
                Instantiator {
                    model: backModel
                    MenuItem {
                        text: model.text
                        onTriggered: controller.backTo(model.text,-1);
                    }
                    onObjectAdded: {
                        backContextMenu.insertItem(index,object)
                        goBackAction.enabled = true;
                    }
                    onObjectRemoved: {
                        backContextMenu.removeItem(object)
                        if (backContextMenu.items.count == 0) goBackAction.enabled = false
                    }
                }
            }
            Menu {
                id: forwardContextMenu
                Instantiator {
                    model: forwardModel
                    MenuItem {
                        text: model.text
                        onTriggered: controller.forwardTo(model.text,-1);
                    }
                    onObjectAdded: {
                        forwardContextMenu.insertItem(index,object)
                        goForwardAction.enabled = true
                    }
                    onObjectRemoved: {
                        forwardContextMenu.removeItem(object)
                        if (forwardContextMenu.items.length==0) goForwardAction.enabled = false;
                    }
                }
            }
            Action {
                id: goBackAction
                enabled: false
            }
            Action {
                id: goForwardAction
                enabled: false
            }
            ToolButton {
                action: goBackAction
                text: "<-"
                onClicked: if (backContextMenu.items.length>0) backContextMenu.popup()
            }
            ToolButton {
                action: goForwardAction
                text: "->"
                onClicked: if (forwardContextMenu.items.length>0) forwardContextMenu.popup()
            }
            ToolButton { text: "Path Editing"; action: path_editing_action }
            ToolButton { text: "API browsing"; action: api_browsing_action }
        }
    }

    Rectangle {
        id: root
        color: backgroundColor
        width: 800; height: 600;
        anchors.fill: parent 
        focus: true
        Keys.onEscapePressed: Qt.quit()
        Keys.onPressed: {
          if ((event.key == Qt.Key_Q) && (event.modifiers & Qt.ControlModifier))
            Qt.quit();
        }

        states: [
            State {
                name: "BROWSE_API"
                PropertyChanges { target: browseAPIContainer; visible: true }
                PropertyChanges { target: editPathsContainer; visible: false }
            },
            State {
                name: "EDIT_PATHS"
                PropertyChanges { target: editPathsContainer; visible: true }
                PropertyChanges { target: browseAPIContainer; visible: false }
            }
        ]
        state: "BROWSE_API"

        ApiBrowser {
            id: browseAPIContainer
            anchors.fill: parent
        }

        PathEditor {
            id: editPathsContainer
            anchors.fill: parent
        }

        function setCurrentPaths() {
            // get OCaml paths and set them to temporary model
            // So hackful because we need to convert QList<String> to Array
            var lst = controller.paths()
            //console.log("got paths from OCaml");
            var ans = [];
            for (var x in lst ) {
              ans.push(lst[x]);
              //console.log(lst[x])
            }
            editPathsContainer.pathModel = ans
        }
        function applyPaths() {
            // transfer selected paths to OCaml
            controller.setPaths(editPathsContainer.pathModel)
        }
    }
}
