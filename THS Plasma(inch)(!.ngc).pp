+ =======================================
+ ---
+ Version 1
+   RJF     09/23/2023 Written
+ =======================================


POST_NAME = "THS Plasma(inch)(*.ngc)"


FILE_EXTENSION = "ngc"

UNITS = "INCHES"

+------------------------------------------------
+    Line terminating characters
+------------------------------------------------

LINE_ENDING = "[13][10]"

+------------------------------------------------
+    Block numbering
+------------------------------------------------

LINE_NUMBER_START     = 0
LINE_NUMBER_INCREMENT = 5
LINE_NUMBER_MAXIMUM = 999999

+================================================
+
+    Formating for variables
+
+================================================

VAR LINE_NUMBER = [N|A|N|1.0]
VAR SPINDLE_SPEED = [S|A|S|1.0]
VAR FEED_RATE = [F|C|F|1.1]
VAR X_POSITION = [X|C|X|1.4]
VAR Y_POSITION = [Y|C|Y|1.4]
VAR Z_POSITION = [Z|C|Z|1.4]
VAR ARC_CENTRE_I_INC_POSITION = [I|A|I|1.4]
VAR ARC_CENTRE_J_INC_POSITION = [J|A|J|1.4]
VAR X_HOME_POSITION = [XH|A|X|1.4]
VAR Y_HOME_POSITION = [YH|A|Y|1.4]
VAR Z_HOME_POSITION = [ZH|A|Z|1.4]
VAR SAFE_Z_HEIGHT = [SAFEZ|A|Z|1.4]

+================================================
+
+    Block definitions for toolpath output
+
+================================================

+---------------------------------------------------
+  Commands output at the start of the file
+---------------------------------------------------

begin HEADER

"%"
""
"(THS vCarve Post)"
"G20" 
"G90 G40"
"G17 G91.1"
"G64 P0.01 Q0.012"
"M52 P1."
"M65 P2."
"M65 P3."
"M68 E3 Q0."
""
"G54"
"F#<_hal[91]plasmac.cut-feed-rate[93]>"
""
"(----- Toolpath [TOOLPATH_NAME] -----)"
""


+---------------------------------------------------
+  Commands output for rapid moves
+---------------------------------------------------

begin RAPID_MOVE

"G0 [X] [Y]"


+---------------------------------------------------
+  Commands output for feed rate moves
+---------------------------------------------------

begin FEED_MOVE

"G1 [X] [Y]"

+---------------------------------------------------
+  Commands output for the first clockwise arc move
+---------------------------------------------------

begin FIRST_CW_ARC_MOVE

"G2 [X] [Y] [I] [J]"


+---------------------------------------------------
+  Commands output for clockwise arc  move
+---------------------------------------------------

begin CW_ARC_MOVE

"G2 [X] [Y] [I] [J]"


+---------------------------------------------------
+  Commands output for the first counterclockwise arc move
+---------------------------------------------------

begin FIRST_CCW_ARC_MOVE

"G3 [X] [Y] [I] [J]"


+---------------------------------------------------
+  Commands output for counterclockwise arc  move
+---------------------------------------------------

begin CCW_ARC_MOVE

"G3 [X] [Y] [I] [J]"


+---------------------------------------------------
+  Commands output for a new segment - toolpath
+  with same toolnumber but maybe different feedrates
+---------------------------------------------------

begin NEW_SEGMENT

""
"(----- Toolpath [TOOLPATH_NAME] -----)"
""



+---------------------------------------------------

+ Commands output for the First Plunge Move, in a series of plunge moves.

+---------------------------------------------------

begin FIRST_PLUNGE_MOVE


"M3 $0 S1"

+---------------------------------------------------

+ Commands output for Plunge Moves

+---------------------------------------------------

begin PLUNGE_MOVE

"M3 $0 S1"

+---------------------------------------------------

+ Commands output for Retract Moves

+---------------------------------------------------

begin RETRACT_MOVE

"M5"
""

+---------------------------------------------------
+  Commands output at the end of the file
+---------------------------------------------------

begin FOOTER

"G0 X0 Y0"
"G90"
"G40"
"M65 P2."
"M65 P3."
"M68 E3 Q0."
"M5"
"M30"
"%"
