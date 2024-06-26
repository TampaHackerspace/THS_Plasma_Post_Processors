/**
  Copyright (C) 2015-2016 by Autodesk, Inc.
  All rights reserved.

  PlasmaC post processor for HSMWorks
  Revision 1
  06/04/2024

*/

description = "Tampa Hackerspace PlasmaC";
vendor = "LinuxCNC";
vendorUrl = "http://www.linuxcnc.org";
legal = "Copyright (C) 2015-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 39000;

longDescription = "Plasmac post processor for Tampa Hackerspace Lightning CNC \
Plasma Table. Emulate a Plasma cutter using milling functions in HSMWorks"
extension = "ngc";
//setCodePage("ascii");

capabilities = CAPABILITY_MILLING ;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.00001, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.00001);
maximumCircularSweep = toRad(360);
allowHelicalMoves = false;
allowedCircularPlanes = undefined;

torchOnFSM = false;



// user-defined property definitions
properties = {
    writeMachine: {
        title: "Write machine settings",
        description: "Output the machine settings in the header of the code.",
        group: "General",
        type: "boolean",
        value: true,
        scope: "post",
    },
    showNotes: {
        title: "Show operation notes",
        description: "Writes operation notes as comments in the outputted code.",
        group: "General",
        type: "boolean",
        value: true,
        scope: "post",
    },
    showSequenceNumbers: {
        title: "Use sequence numbers",
        description: "Use sequence numbers for each block of outputted code.",
        group: "General",
        type: "boolean",
        value: true,
        scope: "post",
    },
    sequenceNumberStart: {
        title: "Start sequence number",
        description: "The number at which to start the sequence numbers.",
        group: "General",
        type: "integer",
        value: 10,
        scope: "post",
    },
    sequenceNumberIncrement: {
        title: "Sequence number increment",
        description: "The amount by which the sequence number is incremented by in each block.",
        group: "General",
        type: "integer",
        value: 5,
        scope: "post",
    },
    separateWordsWithSpace: {
        title: "Separate words with space",
        description: "Adds spaces between words if 'yes' is selected.",
        group: "General",
        type: "boolean",
        value: true,
        scope: "post",
    },
    useAutomaticMaterialSelection: {
        title: "Automatic Material",
        description: "Tool Number will be used to select material settings",
        group: "General",
        type: "boolean",
        value: false,
        scope: "post",
    },
    toolTrack: {
        title: "Blending tolerance",
        description: "Blending tolerance that path blending allows (in mm)",
        group: "Tolerances",
        type: "number",
        value: 0.254,
        scope: "post",
    },
    camTolerance: {
        title: "Naive cam tolerance",
        description: "Linear tolerance for multiple nodes on the same tool path (in mm)",
        group: "Tolerances",
        type: "spatial",
        value: spatial(0.310, MM),
        scope: "post",
    },
    mergeCircles: {
        title: "Merge Circles",
        description: "Combine circles to a single operation when possible.",
        group: "Circles",
        type: "boolean",
        value: false,
        scope: "post",
    }
};


groupDefinitions = {
    General: {
        title: "General",
        description: "Common PlasmaC options",
        order: 10,
        collapsed: false
    },
    Tolerances: {
        title: "Tolerances",
        description: "Machine level tolerances",
        order: 15,
        collapsed: true
    },
    Circles: {
        title: "Circles",
        description: "Circle specifics settings",
        order: 20,
        collapsed: true
    }
}

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

/**
  Writes the specified block.
*/
function writeBlock() {
    var text = formatWords(arguments);
    if (!text) {
        return;
    }
    if (getProperty("showSequenceNumbers")) {
        writeWords2("N" + sequenceNumber, arguments);
        sequenceNumber += getProperty("sequenceNumberIncrement");
        if (sequenceNumber > 99999) {
            sequenceNumber = getProperty("sequenceNumberStart")
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
            writeBlock(gFormat.format(64), pFormat.format((getProperty("toolTrack") / 25.4)), qFormat.format((getProperty("camTolerance") / 25.4)));
            break;
        case MM:
            writeBlock(gFormat.format(64), pFormat.format(getProperty("toolTrack")), qFormat.format(getProperty("camTolerance")));
            break;
    }
}

function onPower(power) {
    if (power) {                                                                //Requested power ON
        writeBlock(mFormat.format(3), $Format.format(0), sFormat.format(1));    //start the torch
    } else {                                                                    //Requested power OFF
        writeBlock(mFormat.format(5));                                          //stop the torch
    }
}

function torchOn(requestedTorchState) {
    if (requestedTorchState) {              //Torch requested ON
        if (torchOnFSM == true) {
            writeComment ("Torch already on");
            return;                         //Torch is already on. no action needed
        } else {
            writeBlock(mFormat.format(3), $Format.format(0), sFormat.format(1));
            torchOnFSM = true;
        }
    } else {                                //Torch requested OFF
        if (torchOnFSM == false) {
            writeComment ("Torch already off");
            return;                         //Torch is already off. no action needed
        } else {
            writeBlock(mFormat.format(5));
            torchOnFSM = false;
        }
    }
    return;
}

function onOpen() {

    if (!getProperty("separateWordsWithSpace")) {
        setWordSeparator("");
    }

    sequenceNumber = getProperty("sequenceNumberStart");

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

    if (getProperty("writeMachine") && (vendor || model || description)) {
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

function commentMovement(movement) {
    switch (movement) {
        case MOVEMENT_CUTTING:
            writeComment("Movement "+movement+" : Standard cutting motion");
            break;

        case MOVEMENT_EXTENDED:
            writeComment("Movement "+movement+" : Extended movement type. Not common");
            break;

        case MOVEMENT_FINISH_CUTTING:
            writeComment("Movement "+movement+" : Finish cutting motion");
            break;

        case MOVEMENT_HIGH_FEED:
            writeComment("Movement "+movement+" : Movement at high feedrate");
            break;

        case MOVEMENT_LEAD_IN:
            writeComment("Movement "+movement+" : Lead-in motion");
            break;

        case MOVEMENT_LEAD_OUT:
            writeComment("Movement "+movement+" : Lead-out motion");
            break;

        case MOVEMENT_LINK_DIRECT:
            writeComment("Movement "+movement+" : Direction (non-cutting) linking move");
            break;

        case MOVEMENT_LINK_TRANSITION:
            writeComment("Movement "+movement+" : Transition (cutting) linking move");
            break;

        case MOVEMENT_PLUNGE:
            writeComment("Movement "+movement+" : Plunging move");
            break;

        case MOVEMENT_PREDRILL:
            writeComment("Movement "+movement+" : Predrilling motion");
            break;

        case MOVEMENT_RAMP:
            writeComment("Movement "+movement+" : Ramping entry motion");
            break;

        case MOVEMENT_RAMP_HELIX:
            writeComment("Movement "+movement+" : Helical ramping motion");
            break;

        case MOVEMENT_RAMP_PROFILE:
            writeComment("Movement "+movement+" : Profile ramping motion");
            break;

        case MOVEMENT_RAMP_ZIG_ZAG:
            writeComment("Movement "+movement+" : Zig-Zag ramping motion");
            break;

        case MOVEMENT_RAPID:
            writeComment("Movement "+movement+" : Rapid movement");
            break;

        case MOVEMENT_REDUCED:
            writeComment("Movement "+movement+" : Reduced cutting motion");
            break;

        default:
            writeComment("Movement "+movement+" : UNKNOWN ");
            break;
    }
}

function onMovement(movement) {
    //commentMovement(movement);
    if (movement == MOVEMENT_PLUNGE) torchOn(true);
    if (movement == MOVEMENT_RAPID) torchOn(false);
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


    if (getProperty("showNotes") && hasParameter("notes")) {
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

            case TOOL_MILLING_END_FLAT:
                writeComment("Flat endmill simulated plasma cutter");
                break;

            default:
                error(localize("The CNC does not support the required tool. tooltype=" + tool.type));
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
        if (getProperty("useAutomaticMaterialSelection")) {
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
    //writeComment("Radius Change Event --> " + radiusCompensation);
    // radiusCompensation: 
    //  0 = Center/OFF 
    //  1 = Compensation_Left
    //  2 = Compensation_Right

    switch (radiusCompensation) {
        case 0:
            writeComment("Radius Compensation requested OFF");
            break;
        case 1:
            writeComment("Radius Compensation requested LEFT");
            break;
        case 2:
            writeComment("Radius Compensation requested RIGHT");
            break;
        default:
            writeComment("Unkown Radius Compensation request -->" + radiusCompensation);
    }

    if (radiusCompensation == 0) {
        writeBlock(gFormat.format(40));
    } else {
        pendingRadiusCompensation = radiusCompensation;
    }
}

function onParameter(name, value) {
    switch (name) {
        case "action":
            //writeComment ("ACTION Param Value = " + value);
            let valueArray = value.split(",");
            if (valueArray[0] === "SPEED"){
               writeComment("Setting movement velocity to " + valueArray[1] + " percent");
               writeBlock(mFormat.format(67), eFormat.format(3), qFormat.format(parseInt(valueArray[1])));
            }
            return;
        default:
            //writeComment ("UNKNOWN Parameter = " + name + " -- Value = " + value);
            return;
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
    } else if (nextCircle && getProperty("MergeCircles")) {
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
                writeBlock(gMotionModal.format(circleData.clockwise ? 2 : 3), xOutput.format(circleData.end.x), yOutput.format(circleData.end.y), iOutput.format(circleData.center.x - circleData.start.x, 0), jOutput.format(circleData.center.y - circleData.start.y, 0));
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


function onCommand(command) {
	writeComment("Command - " + command );
    switch (command) {
        case COMMAND_STOP:
            writeBlock(mFormat.format(0));
            forceSpindleSpeed = true;
            return;
        case COMMAND_START_SPINDLE:
            onCommand(COMMAND_SPINDLE_CLOCKWISE)
            return;
        case COMMAND_BREAK_CONTROL:
            return;
        default:
            return;
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
