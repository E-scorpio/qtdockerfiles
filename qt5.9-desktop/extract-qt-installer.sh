#!/bin/bash
# QT-CI Project
# License: Apache-2.0
# https://github.com/benlau/qtci

function usage() {
    echo "Usage:"
    echo "extract-qt-installer qt-installer output_path"
    echo "extract-qt-installer --list-packages qt-installer"
    exit -1
}

unset DISPLAY
echo $DISPLAY

LIST_PACKAGES=0

getopt --test > /dev/null 2>&1
GETOPT_RET_CODE=$?

set -e #quit on error

if [ "$GETOPT_RET_CODE" != "4" ]
then
    echo "Warning: gnu-getopt is not installed. Long parameter like '--list-package' will not be working. Please install gnu-getopt by 'brew install gnu-getopt'"   
else

	OPTS=`getopt -o l --long list-packages --long disable-progress-report -n "extract-qt-installer" -- "$@"`

    eval set -- "$OPTS"

    while true
    do
      case "$1" in
        --list-packages)
          LIST_PACKAGES=1
          shift;;
	    --disable-progress-report)
	      DISABLE_PROGRESS_REPORT=1
	      shift;;
        --) shift;break;;
        *) shift;;
      esac
    done
fi


export PATH=$PATH:$PWD
export WORKDIR=$PWD
INSTALLER=$1
OUTPUT=$2
SCRIPT="$(mktemp /tmp/tmp.XXXXXXXXX)"
PACKAGES=$QT_CI_PACKAGES

if [ $LIST_PACKAGES -gt 0 ]
then 

	if [ $# -lt 1 ]
	then
		usage
	fi
	
	OUTPUT="/tmp/Qt"

else

	if [ $# -lt 2 ]
	then
		usage
	fi

	if [[ ! "${OUTPUT:0:1}" = "/" ]] 
	then 
		echo output path must be an absolute path
		exit -1
	fi
    
fi

cat <<EOF > $SCRIPT

function abortInstaller()
{
    installer.setDefaultPageVisible(QInstaller.Introduction, false);
    installer.setDefaultPageVisible(QInstaller.TargetDirectory, false);
    installer.setDefaultPageVisible(QInstaller.ComponentSelection, false);
    installer.setDefaultPageVisible(QInstaller.ReadyForInstallation, false);
    installer.setDefaultPageVisible(QInstaller.StartMenuSelection, false);
    installer.setDefaultPageVisible(QInstaller.PerformInstallation, false);
    installer.setDefaultPageVisible(QInstaller.LicenseCheck, false);

    var abortText = "<font color='red' size=3>" + qsTr("Installation failed:") + "</font>";

    var error_list = installer.value("component_errors").split(";;;");
    abortText += "<ul>";
    // ignore the first empty one
    for (var i = 0; i < error_list.length; ++i) {
        if (error_list[i] !== "") {
            log(error_list[i]);
            abortText += "<li>" + error_list[i] + "</li>"
        }
    }
    abortText += "</ul>";
    installer.setValue("FinishedText", abortText);
}

function log() {
    var msg = ["QTCI: "].concat([].slice.call(arguments));
    console.log(msg.join(" "));
}

function printObject(object) {
	var lines = [];
	for (var i in object) {
		lines.push([i, object[i]].join(" "));
	}
	log(lines.join(","));
}

var status = {
	widget: null,
	finishedPageVisible: false,
	installationFinished: false
}

function tryFinish() {

	if (status.finishedPageVisible && status.installationFinished) {
		if (status.widget.RunItCheckBox) {
			status.widget.RunItCheckBox.setChecked(false);
		}
		log("Press Finish Button");
	    gui.clickButton(buttons.FinishButton);
	}
}

function Controller() {
    installer.installationFinished.connect(function() {
		status.installationFinished = true;
        gui.clickButton(buttons.NextButton);
        tryFinish();
    });
    installer.setMessageBoxAutomaticAnswer("OverwriteTargetDirectory", QMessageBox.Yes);
    installer.setMessageBoxAutomaticAnswer("installationErrorWithRetry", QMessageBox.Ignore);
    
    // Allow to cancel installation for arguments --list-packages
    installer.setMessageBoxAutomaticAnswer("cancelInstallation", QMessageBox.Yes);
}

Controller.prototype.WelcomePageCallback = function() {
    log("Welcome Page");
    gui.clickButton(buttons.NextButton);

    var widget = gui.currentPageWidget();

    widget.completeChanged.connect(function() {
        gui.clickButton(buttons.NextButton);
    });
}

Controller.prototype.CredentialsPageCallback = function() {
	
	var login = installer.environmentVariable("QT_CI_LOGIN");
	var password = installer.environmentVariable("QT_CI_PASSWORD");

	if (login === "" || password === "") {
		gui.clickButton(buttons.CommitButton);
	}
	
    var widget = gui.currentPageWidget();

	widget.loginWidget.EmailLineEdit.setText(login);

	widget.loginWidget.PasswordLineEdit.setText(password);

    gui.clickButton(buttons.CommitButton);
}

Controller.prototype.ComponentSelectionPageCallback = function() {
	log("ComponentSelectionPageCallback");

    if ($LIST_PACKAGES) {
      var components = installer.components();
      log("Available components: " + components.length);
      var packages = ["Packages: "];

      for (var i = 0 ; i < components.length ;i++) {
		  packages.push(components[i].name);
      }
	  log(packages.join(" "));
      
      gui.clickButton(buttons.CancelButton);
      return;
    }

    log("Select components");

    function trim(str) {
        return str.replace(/^ +/,"").replace(/ *$/,"");
    }

    var widget = gui.currentPageWidget();

    var packages = trim("$PACKAGES").split(",");
    if (packages.length > 0 && packages[0] !== "") {
        widget.deselectAll();
        for (var i in packages) {
            var pkg = trim(packages[i]);
	        log("Select " + pkg);
	        widget.selectComponent(pkg);
        }
    } else {
       log("Use default component list");
    }

    gui.clickButton(buttons.NextButton);
}

Controller.prototype.IntroductionPageCallback = function() {
    log("Introduction Page");
    log("Retrieving meta information from remote repository");
    gui.clickButton(buttons.NextButton);
}


Controller.prototype.TargetDirectoryPageCallback = function() {
    log("Set target installation page: $OUTPUT");
    var widget = gui.currentPageWidget();

    if (widget != null) {
        widget.TargetDirectoryLineEdit.setText("$OUTPUT");
    }
    
    gui.clickButton(buttons.NextButton);
}

Controller.prototype.LicenseAgreementPageCallback = function() {
    log("Accept license agreement");
    var widget = gui.currentPageWidget();

    if (widget != null) {
        widget.AcceptLicenseRadioButton.setChecked(true);
    }

    gui.clickButton(buttons.NextButton);

}

Controller.prototype.ReadyForInstallationPageCallback = function() {
    log("Ready to install");
    gui.clickButton(buttons.CommitButton);
}

Controller.prototype.PerformInstallationPageCallback = function() {
    log("PerformInstallationPageCallback");
    gui.clickButton(buttons.CommitButton);
}

Controller.prototype.FinishedPageCallback = function() {
    log("FinishedPageCallback");

    var widget = gui.currentPageWidget();

    if (widget.LaunchQtCreatorCheckBoxForm) {
        // No this form for minimal platform
        widget.LaunchQtCreatorCheckBoxForm.launchQtCreatorCheckBox.setChecked(false);
    }
    
    if (widget.RunItCheckBox) {
		// LaunchQtCreatorCheckBoxForm may not works for newer version.
		widget.RunItCheckBox.setChecked(false);
	}

	// Bug? Qt 5.9.5 and Qt 5.9.6 installer show finished page before the installation completed
	// Don't press "finishButton" immediately
    
	status.finishedPageVisible = true;
	status.widget = widget;
	tryFinish();   
}

EOF

chmod u+x $1

if [ -n "$DISABLE_PROGRESS_REPORT" ]
then
	QT_QPA_PLATFORM=minimal $INSTALLER $ARGS --script $SCRIPT
else
	ARGS="-v"

	if [ -n "$VERBOSE" ]
	then
		QT_QPA_PLATFORM=minimal $INSTALLER $ARGS --script $SCRIPT
	else
		QT_QPA_PLATFORM=minimal $INSTALLER $ARGS --script $SCRIPT | grep "\(QTCI\|operation\)"
	fi
fi


