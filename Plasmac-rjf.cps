/**
  Copyright (C) 2015-2016 by Autodesk, Inc.
  All rights reserved.

  PlasmaC post processor
  Revision 0
  09/01/2019

  $Revision: 42319 7b9a1dc9f1343527d18a6a1d92801fb7a4787cad $
  $Date: 2019-05-31 12:02:09 $
  
  FORKID {51C1E5C7-D09E-458F-AC35-4A2CE1E0AE32}
*/

description = "PlasmaC";
vendor = "LinuxCNC";
vendorUrl = "http://www.linuxcnc.org";
legal = "Copyright (C) 2015-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 39000;

longDescription = "Plasmac post processor"
extension = "ngc";
setCodePage("ascii");

capabilities = CAPABILITY_JET;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.00001, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.00001);
maximumCircularSweep = toRad(360);
allowHelicalMoves = false;
allowedCircularPlanes = undefined;



// user-defined properties
properties = {
    writeMachine: true, // write machine
    showSequenceNumbers: true, // show sequence numbers
    sequenceNumberStart: 10, // first sequence number
    sequenceNumberIncrement: 5, // increment for sequence numbers
    separateWordsWithSpace: true, // specifies that the words should be separated with a white space
    toolTrack: spatial(0.254, MM),
    camTolerance: spatial(0.254, MM),
    showNotes: true,
    slowSpeedPercentage: 60,
    MergeCircles: false,
    useAutomaticMaterialSelection: false,
};

// user-defined property definitions
propertyDefinitions = {
    writeMachine: { title: "Write machine", description: "Output the machine settings in the header of the code.", group: 0, type: "boolean" },
    useAutomaticMaterialSelection: { title: "Automatic Material", description: "Tool Number will be used to select material settings", group: 1, type: "boolean" },
    showSequenceNumbers: { title: "Use sequence numbers", description: "Use sequence numbers for each block of outputted code.", group: 1, type: "boolean" },
    sequenceNumberStart: { title: "Start sequence number", description: "The number at which to start the sequence numbers.", group: 1, type: "integer" },
    sequenceNumberIncrement: { title: "Sequence number increment", description: "The amount by which the sequence number is incremented by in each block.", group: 1, type: "integer" },
    separateWordsWithSpace: { title: "Separate words with space", description: "Adds spaces between words if 'yes' is selected.", type: "boolean" },
    toolTrack: { title: "Blending tolerance", description: "Blending tolerance that path blending allows (in mm)", group: 2, type: "number" },
    camTolerance: { title: "Naive cam tolerance", description: "Linear tolerance for multiple nodes on the same tool path (in mm)", group: 2, type: "number" },
    showNotes: { title: "Show notes", description: "Writes operation notes as comments in the outputted code.", group: 3, type: "boolean" },
    slowSpeedPercentage: { title: "Slow Speed Percentage", description: "What percentage of normal speed to use for cutting small circles", type: "integer" }
};

// wcs definiton
wcsDefinitions = {
    useZeroOffset: false,
    wcs: [
        { name: "Standard", format: "G", range: [54, 59] },
        { name: "Extended", format: "G59.", range: [1, 3] },
        { name: "Extra", format: "G54.1 P", range: [10, 500] }
    ]
};

var permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,=_-";

var gFormat = createFormat({ prefix: "G", decimals: 1, forceDecimal: false });
var mFormat = createFormat({ prefix: "M", decimals: 1, forceDecimal: false });
var sFormat = createFormat({ prefix: "S", decimals: 0 });
var pFormat = createFormat({ prefix: "P", decimals: 3, forceDecimal: true });
var qFormat = createFormat({ prefix: "Q", decimals: 3, forceDecimal: true });
var lFormat = createFormat({ prefix: "L", decimals: 0 });
var eFormat = createFormat({ prefix: "E", decimals: 0 });
var $Format = createFormat({ prefix: "$", decimals: 0 });

var xyzFormat = createFormat({ decimals: (unit == MM ? 5 : 6), forceDecimal: true });
var feedFormat = createFormat({ decimals: (unit == MM ? 1 : 2), forceDecimal: true });
var secFormat = createFormat({ decimals: 3, forceDecimal: true }); // seconds - range 0.001-99999.999
var rpmFormat = createFormat({ decimals: 0 });

var xOutput = createVariable({ prefix: "X" }, xyzFormat);
var yOutput = createVariable({ prefix: "Y" }, xyzFormat);
var feedOutput = createVariable({ prefix: "F" }, feedFormat);
var sOutput = createVariable({ prefix: "S", force: true }, rpmFormat);

// circular output
var iOutput = createReferenceVariable({ prefix: "I" }, xyzFormat);
var jOutput = createReferenceVariable({ prefix: "J" }, xyzFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({ onchange: function () { gMotionModal.reset(); } }, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21
var gCutCompModal = createModal({}, gFormat); //G40-42 (cutter compensation)
var gPathBlendModal = createModal({}, gFormat); //G64 (path blending)

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;
var smallHoleSection = false;
var centerPunch = false;

/**
  Writes the specified block.
*/
function writeBlock() {
    var text = formatWords(arguments);
    if (!text) {
        return;
    }
    if (properties.showSequenceNumbers) {
        writeWords2("N" + sequenceNumber, arguments);
        sequenceNumber += properties.sequenceNumberIncrement;
        if (sequenceNumber > 99999) {
            sequenceNumber = properties.sequenceNumberStart
        }
    } else {
        writeWords(arguments);
    }
}

function formatComment(text) {
    return "(" + filterText(String(text).toUpperCase(), permittedCommentChars) + ")";
}


function writeComment(text) {
    writeln(formatComment(text));
}
/***********************************
 * Added for Plasmac               *
 ***********************************/
function setTolerances() {
    switch (unit) {
        case IN:
            writeBlock(gFormat.format(64), pFormat.format((properties.toolTrack / 25.4)), qFormat.format((properties.camTolerance / 25.4)));
            break;
        case MM:
            writeBlock(gFormat.format(64), pFormat.format(properties.toolTrack), qFormat.format(properties.camTolerance));
            break;
    }
}

function onPower(power) {
    if (power) {
        //if (!smallHoleSection) {
        writeBlock(mFormat.format(3), $Format.format(0), sFormat.format(1));
        //}
    } else {
        writeBlock(mFormat.format(5));
    }
}

function onOpen() {

    if (!properties.separateWordsWithSpace) {
        setWordSeparator("");
    }

    sequenceNumber = properties.sequenceNumberStart;

    if (programName) {
        writeComment(programName);
    }
    if (programComment) {
        writeComment(programComment);
    }

    // dump machine configuration
    var vendor = machineConfiguration.getVendor();
    var model = machineConfiguration.getModel();
    var description = machineConfiguration.getDescription();

    if (properties.writeMachine && (vendor || model || description)) {
        writeComment(localize("Machine"));
        if (vendor) {
            writeComment("  " + localize("vendor") + ": " + vendor);
        }
        if (model) {
            writeComment("  " + localize("model") + ": " + model);
        }
        if (description) {
            writeComment("  " + localize("description") + ": " + description);
        }
    }

    if ((getNumberOfSections() > 0) && (getSection(0).workOffset == 0)) {
        for (var i = 0; i < getNumberOfSections(); ++i) {
            if (getSection(i).workOffset > 0) {
                error(localize("Using multiple work offsets is not possible if the initial work offset is 0."));
                return;
            }
        }
    }
    switch (unit) {
        case IN:
            writeBlock(gUnitModal.format(20));
            break;
        case MM:
            writeBlock(gUnitModal.format(21));
            break;
    }
    // absolute coordinates and feed per min
    writeBlock(gAbsIncModal.format(90), gCutCompModal.format(40));
    writeBlock(gPlaneModal.format(17), gFormat.format(91.1));
    setTolerances(); // Plasmac specific
    writeBlock(mFormat.format(52), pFormat.format(1)); //enable reverse run, pause motion
    writeBlock(mFormat.format(65), pFormat.format(2)); //THC Immediate
    writeBlock(mFormat.format(65), pFormat.format(3)); //Torch Enable Immediate
    writeBlock(mFormat.format(68), eFormat.format(3), qFormat.format(0)); //velocity control
}

function onComment(message) {
    writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
    xOutput.reset();
    yOutput.reset();
    //zOutput.reset(); plasmac does not use Z output - all handled by component
}

function forceFeed() {
    currentFeedId = undefined;
    feedOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
    forceXYZ();
    forceFeed();
}

function onSection() {
    writeln("");

    var insertToolCall = isFirstSection() ||
        currentSection.getForceToolChange && currentSection.getForceToolChange() ||
        (tool.number != getPreviousSection().getTool().number);

    var retracted = false; // specifies that the tool has been retracted to the safe plane

    if (hasParameter("operation-comment")) {
        var comment = getParameter("operation-comment");
        if (comment) {
            writeComment(comment);
        }
    }


    if (hasParameter("operation:doLeadIn") && getParameter("operation:doLeadIn") == 0) {
        smallHoleSection = true;
        if (!centerPunch) {
            writeComment("--------------------------------------------------------------------------------------------------");
            writeComment("- This section is set up to cut small holes only.                                                -");
            writeComment("- It will automatically slow the cut speed for the hole(s) based on the setting in the parameters. -");
            writeComment("- It will also create an arc lead-in for each hole starting at the center of the hole.           -");
            writeComment("- Any other type of operations in this section will not work correctly                           -");
            writeComment("- This setup has occurred due to disabling lead in on the leads page                             -");
            writeComment("- Be certain you have also set Pierce Clearance to 0 or you will not get the correct results     -");
            writeComment("--------------------------------------------------------------------------------------------------");
        } else {
            writeComment("--------------------------------------------------------------------------------------------------");
            writeComment("- This section is set up to center punch the selected holes.                                     -");
            writeComment("- Any other type of operations in this section will not work correctly                           -");
            writeComment("--------------------------------------------------------------------------------------------------");
            writeBlock(feedOutput.format(999999));
        }
    } else {
        if (smallHoleSection) {
            writeComment("--------------------------------------------------");
            writeComment("- This section has reverted to normal operation. -");
            writeComment("--------------------------------------------------");
        } else {
            writeComment("---------------------");
            writeComment("- Normal operation. -");
            writeComment("---------------------");
        }
        smallHoleSection = false;
    }

    if (properties.showNotes && hasParameter("notes")) {
        var notes = getParameter("notes");
        if (notes) {
            var lines = String(notes).split("\n");
            var r1 = new RegExp("^[\\s]+", "g");
            var r2 = new RegExp("[\\s]+$", "g");
            for (line in lines) {
                var comment = lines[line].replace(r1, "").replace(r2, "");
                if (comment) {
                    writeComment(comment);
                }
            }
        }
    }


    if (insertToolCall) {
        retracted = true;

        switch (tool.type) {
            case TOOL_PLASMA_CUTTER:
                writeComment("Plasma cutting");
                break;

            default:
                error(localize("The CNC does not support the required tool."));
                return;
        }

        switch (currentSection.jetMode) {
            case JET_MODE_THROUGH:
                writeComment("THROUGH CUTTING");
                break;

            default:
                error(localize("Unsupported cutting mode."));
                return;
        }

        if (tool.comment) {
            writeComment(tool.comment);
        }
        writeln("");
    }

    if (currentSection.workOffset != currentWorkOffset) {
        writeBlock(currentSection.wcs);
        currentWorkOffset = currentSection.workOffset;
    }

    forceXYZ();

    forceAny();
    gMotionModal.reset();

    var initialPosition = getFramePosition(currentSection.getInitialPosition());

    if (insertToolCall || retracted) {
        gMotionModal.reset();
        /********************************************
         * Set up the new tool (Plasmac specific)   *
         * Uses the plasmac material table          *
         * Tool number in Fusion360 will correspond *
         * to a material number in plasmac material *
         * table.                                   *
         ********************************************/
        if (properties.useAutomaticMaterialSelection) {
            writeBlock(mFormat.format(190), pFormat.format(tool.number));
            writeBlock(mFormat.format(66), pFormat.format(3), lFormat.format(3), qFormat.format(1));
        }


        writeBlock("F#<_hal[plasmac.cut-feed-rate]>");
        /*******************************************/

        writeBlock(gAbsIncModal.format(90))
        writeBlock(
            gMotionModal.format(0),
            xOutput.format(initialPosition.x),
            yOutput.format(initialPosition.y)
        );
        gMotionModal.reset();
    } else {
        writeBlock(gAbsIncModal.format(90))
        writeBlock(
            gMotionModal.format(0),
            xOutput.format(initialPosition.x),
            yOutput.format(initialPosition.y)
        );
    }
}

function onDwell(seconds) {
    if (seconds > 99999.999) {
        warning(localize("Dwelling time is out of range."));
    }
    seconds = clamp(0.001, seconds, 99999.999);
    writeBlock(gFeedModeModal.format(94), gFormat.format(4), "P" + secFormat.format(seconds));
}

function onCycle() {
    onError("Drilling is not supported by CNC Plasma.");
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
    // writeComment("Radius Change Event --> " + radiusCompensation);
    // radiusCompensation: 
    //  0 = Center/OFF 
    //  1 = Compensation_Left
    //  2 = Compensation_Right

    if (radiusCompensation == 0) {
        writeBlock(gFormat.format(40));
    } else {
        pendingRadiusCompensation = radiusCompensation;
    }

    // if (pendingRadiusCompensation >= 0) {
    //     pendingRadiusCompensation = -1;
    // switch (radiusCompensation) {
    //     case RADIUS_COMPENSATION_LEFT:
    //         writeBlock(gFormat.format(41.1), "D#<_hal[plasmac_run.kerf-width-f]>");
    //         break;
    //     case RADIUS_COMPENSATION_RIGHT:
    //         writeBlock(gFormat.format(42.1), "D#<_hal[plasmac_run.kerf-width-f]>");
    //         break;
    //     default:
    //         writeBlock(gFormat.format(40));
    // }
    // }
    // pendingRadiusCompensation = radiusCompensation;
}

function onParameter(name, value) {
    if (name == "action") {
        var sText1 = String(value).toUpperCase();
        var sText2 = new Array();
        sText2 = sText1.split(":")
        if (sText2[0] == "CENTERPUNCH") {
            if (sText2[1] == "ON") {
                centerPunch = true;
            } else {
                centerPunch = false;
                writeBlock("F#<_hal[plasmac.cut-feed-rate]>");
            }
        }
    }
}
function onRapid(_x, _y, _z) {
    var x = xOutput.format(_x);
    var y = yOutput.format(_y);
    if (x || y) {
        if (pendingRadiusCompensation >= 0) {
            error(localize("Radius compensation mode cannot be changed at rapid traversal."));
            return;
        }
        writeBlock(gMotionModal.format(0), x, y);
        forceFeed();
    }
}

function onLinear(_x, _y, _z, feed) {
    var x = xOutput.format(_x);
    var y = yOutput.format(_y);
    if (x || y) {
        if (pendingRadiusCompensation >= 0) {
            pendingRadiusCompensation = -1;
            switch (radiusCompensation) {
                case 1: //Compensate_Left
                    writeBlock(gFormat.format(41.1), "D#<_hal[plasmac_run.kerf-width-f]>");
                    writeBlock(gMotionModal.format(1), x, y);
                    break;
                case 2: //Compensate_Right
                    writeBlock(gFormat.format(42.1), "D#<_hal[plasmac_run.kerf-width-f]>");
                    writeBlock(gMotionModal.format(1), x, y);
                    break;
                default:
                    writeBlock(gFormat.format(40));
                    writeBlock(gMotionModal.format(1), x, y);
            }
        } else {
            writeBlock(gMotionModal.format(1), x, y);
        }
    }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
    error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
    error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

/************************* New onCircular function *****************************/
var circleBuffer;
var circleIsBuffered = false;
var circleStart;
function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
    var nextCircle = getNextRecord().getType() == 11; // RECORD_CIRCULAR is 10, but should be 11
    if (circleIsBuffered) {
        if (Vector.diff(circleBuffer.center, new Vector(cx, cy, cz)).length < toPreciseUnit(0.2, MM)) {
            circleBuffer.sweep += getCircularSweep();
            circleBuffer.end = new Vector(x, y, z);
            if (circleBuffer.sweep >= (Math.PI * 2 - toRad(0.01)) || !nextCircle) {
                writeCircle(circleBuffer, feed);
            }
            return;
        }
    } else if (nextCircle && properties.MergeCircles) {
        circleBuffer = {
            center: new Vector(cx, cy, cz),
            start: getCurrentPosition(),
            end: new Vector(x, y, z),
            clockwise: clockwise,
            radius: getCircularRadius(),
            sweep: getCircularSweep()
        };
        circleStart = getCurrentPosition();
        circleIsBuffered = true;
        return;
    }
    if (circleIsBuffered) {
        writeCircle(circleBuffer, feed);
    }

    circleBuffer = {
        center: new Vector(cx, cy, cz),
        start: getCurrentPosition(),
        end: new Vector(x, y, z),
        clockwise: clockwise,
        radius: getCircularRadius(),
        sweep: getCircularSweep()
    };
    circleStart = getCurrentPosition();
    circleIsBuffered = true;
    writeCircle(circleBuffer, feed);
    return;
}






//function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
function writeCircle(circleData, feed) {
    circleIsBuffered = false;
    setCurrentPosition(circleStart);

    if (pendingRadiusCompensation >= 0) {
        error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
        return;
    }

    var start = getCurrentPosition();
    var slowedCutting = false;
    if (circleBuffer.sweep >= (Math.PI * 2 - toRad(0.01))) {
        switch (getCircularPlane()) {
            case PLANE_XY:
                if (smallHoleSection) {
                    var radiusOfCircle = circleData.radius;
                    var toolRadius = (getParameter("operation:tool_kerfWidth")) / 2;
                    //var endXArc = circleData.center.cx + (((circleData.end.x-circleData.center.cx)*(radiusOfCircle-toolRadius))/radiusOfCircle);
                    //var endYArc = circleData.center.cy + (((circleData.end.y-circleData.center.cy)*(radiusOfCircle-toolRadius))/radiusOfCircle);
                    var arcCenterX = ((circleData.end.x - circleData.center.x) / 2) + circleData.center.x;
                    var arcCenterY = ((circleData.end.y - circleData.center.y) / 2) + circleData.center.y;
                    var arcI = arcCenterX - circleData.center.x;
                    var arcJ = arcCenterY - circleData.center.y;
                    writeBlock(gMotionModal.format(0), xOutput.format(circleData.center.x), yOutput.format(circleData.center.y)); //move to start of entry arc - center of the hole
                    if (centerPunch) {
                        writeComment("CENTER PUNCH THE HOLE ONLY");
                        //writeBlock(feedOutput.format(99999));
                        writeBlock(mFormat.format(3), $Format.format(2), sFormat.format(1)); //start the torch
                        writeBlock(gFormat.format(91));
                        writeBlock(gFormat.format(1), xOutput.format(0.00001));
                        writeBlock(gFormat.format(90));
                        //writeBlock("F#<_hal[plasmac.cut-feed-rate]>");
                        //writeBlock(gFormat.format(0));
                    } else {
                        writeComment("SMALL HOLE WITH ARC LEAD-IN FROM CENTER POINT AND 4MM OVERCUT WITH TORCH OFF");
                        writeBlock(mFormat.format(3), $Format.format(0), sFormat.format(1)); //start the torch
                        writeBlock(mFormat.format(67), eFormat.format(3), qFormat.format(properties.slowSpeedPercentage)); //slow the cutting speed
                        writeBlock(gMotionModal.format(circleData.clockwise ? 2 : 3), xOutput.format(circleData.end.x), yOutput.format(circleData.end.y), iOutput.format(arcI, 0), jOutput.format(arcJ, 0)); //create lead in arc
                        writeBlock(gMotionModal.format(circleData.clockwise ? 2 : 3), xOutput.format(circleData.end.x), yOutput.format(circleData.end.y), iOutput.format(circleData.center.x - circleData.start.x, 0), jOutput.format(circleData.center.y - circleData.start.y, 0)); //cut the circle

                        // Turn off the torch and extend the cut 4mm
                        switch (unit) {
                            case IN:
                                cosA = Math.cos(0.157 / radiusOfCircle);
                                sinA = Math.sin(0.157 / radiusOfCircle);
                                break;
                            case MM:
                                cosA = Math.cos(4 / radiusOfCircle);
                                sinA = Math.sin(4 / radiusOfCircle);
                                break;
                        }
                        cosB = ((circleData.end.x - circleData.center.x) / radiusOfCircle);
                        sinB = ((circleData.end.y - circleData.center.y) / radiusOfCircle);
                        writeBlock(mFormat.format(62), pFormat.format(3)); //turn off torch with next motion
                        if (circleData.clockwise) {
                            newEndX = circleData.center.x + radiusOfCircle * ((cosB * cosA) + (sinB * sinA));
                            newEndY = circleData.center.y + radiusOfCircle * ((sinB * cosA) - (cosB * sinA));
                        } else {
                            newEndX = circleData.center.x + radiusOfCircle * ((cosB * cosA) - (sinB * sinA));
                            newEndY = circleData.center.y + radiusOfCircle * ((sinB * cosA) + (cosB * sinA));
                        }
                        writeBlock(gMotionModal.format(circleData.clockwise ? 2 : 3), xOutput.format(newEndX), yOutput.format(newEndY), iOutput.format(circleData.center.x - circleData.start.x, 0), jOutput.format(circleData.center.y - circleData.start.y, 0));
                        writeBlock(mFormat.format(63), pFormat.format(3));// allow torch to be turned on again (syncronized with motion)
                        // End of cut extension code
                        slowedCutting = false;
                        writeBlock(mFormat.format(67), eFormat.format(3), qFormat.format(100)); //set speed back to 100%
                    }
                } else {
                    writeBlock(gMotionModal.format(circleData.clockwise ? 2 : 3), xOutput.format(circleData.end.x), yOutput.format(circleData.end.y), iOutput.format(circleData.center.x - circleData.start.x, 0), jOutput.format(circleData.center.y - circleData.start.y, 0));
                }
                break;
            default:
                linearize(tolerance);
        }
    } else {
        switch (getCircularPlane()) {
            case PLANE_XY:
                writeBlock(gMotionModal.format(circleData.clockwise ? 2 : 3), xOutput.format(circleData.end.x), yOutput.format(circleData.end.y), iOutput.format(circleData.center.x - circleData.start.x, 0), jOutput.format(circleData.center.y - circleData.start.y, 0));
                break;
            default:
                linearize(tolerance);
        }
    }





}

var mapCommand = {
    COMMAND_STOP: 0,
    COMMAND_OPTIONAL_STOP: 1,
    COMMAND_END: 2,
    COMMAND_SPINDLE_CLOCKWISE: 3,
    COMMAND_SPINDLE_COUNTERCLOCKWISE: 4,
    COMMAND_STOP_SPINDLE: 5
};

function onCommand(command) {
    switch (command) {
        case COMMAND_STOP:
            writeBlock(mFormat.format(0));
            forceSpindleSpeed = true;
            return;
        case COMMAND_START_SPINDLE:
            onCommand(COMMAND_SPINDLE_CLOCKWISE)
            return;
        case COMMAND_POWER_ON:
            return;
        case COMMAND_POWER_OFF:
            return;
        case COMMAND_BREAK_CONTROL:
            return;
    }

    var stringId = getCommandStringId(command);
    var mcode = mapCommand[stringId];
    if (mcode != undefined) {
        writeBlock(mFormat.format(mcode));
    } else {
        onUnsupportedCommand(command);
    }
}

function onSectionEnd() {
    forceAny();
}

function onClose() {
    writeln("");

    onImpliedCommand(COMMAND_END);
    onImpliedCommand(COMMAND_STOP_SPINDLE);
    writeBlock(gFormat.format(0), xOutput.format(0), yOutput.format(0));
    writeBlock(gFormat.format(90));
    writeBlock(gFormat.format(40));
    writeBlock(mFormat.format(65), pFormat.format(2));
    writeBlock(mFormat.format(65), pFormat.format(3));
    writeBlock(mFormat.format(68), eFormat.format(3), qFormat.format(0));
    writeBlock(mFormat.format(5));
    writeBlock(mFormat.format(30)); // stop program
}
