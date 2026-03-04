# quick note to self: run from WSS_Py_Wrapper directory as:
# python -m wss_py_wrapper.3ChannelCalibration

import sys
from pathlib import Path
from dataclasses import replace

from .stimulation_controller import StimulationController

from PyQt6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QMainWindow,
    QPushButton,
    QStackedLayout,
    QVBoxLayout,
    QWidget,
    QLabel,
    QCheckBox,
    QSlider,
    QLineEdit,
    QGridLayout
)

def _run_interactive_loop(controller: StimulationController) -> None:
    running = True

    try:
        while running:
            try:
                raw = input("> ").strip()
            except EOFError:
                break

            if not raw:
                continue

            parts = raw.split()
            cmd = parts[0].lower()

            try:
                if cmd == "help":
                    _print_command_help()
                elif cmd in ("quit", "exit"):
                    running = False
                elif cmd == "start":
                    controller.StartStimulation()
                    print("Stim start requested.")
                elif cmd == "stop":
                    controller.StopStimulation()
                    print("Stim stop requested.")
                elif cmd == "status":
                    print(
                        f"Ready={controller.Ready()}, Started={controller.Started()}, "
                        f"ModeValid={controller.isModeValid()}, BasicSupported={controller.BasicSupported}"
                    )
                elif cmd == "reload-core":
                    controller.LoadCoreConfigFile()
                    print("Core config reloaded.")
                elif cmd == "reload-params":
                    if len(parts) > 1:
                        controller.LoadParamsJson(parts[1])
                    else:
                        controller.LoadParamsJson()
                    print("Params reloaded.")
                elif cmd == "save-params":
                    controller.SaveParamsJson()
                    print("Params saved.")
                elif cmd == "stim":
                    if len(parts) < 3:
                        print("Usage: stim <finger|chX> <magnitude>")
                        continue
                    magnitude = float(parts[2])
                    controller.StimWithMode(parts[1], magnitude)
                elif cmd == "analog":
                    if len(parts) < 3:
                        print("Usage: analog <finger|chX> <pw> [amp] [ipi]")
                        continue
                    pw = int(parts[2])
                    amp = int(parts[3]) if len(parts) > 3 else 3
                    ipi = int(parts[4]) if len(parts) > 4 else 10
                    controller.StimulateAnalog(parts[1], pw, amp, ipi)
                else:
                    print("Unknown command. Type 'help' to list options.")
            except Exception as ex:
                print(f"Command failed: {ex}")
    finally:
        controller.StopStimulation()
        controller.Shutdown()



#GUI
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Quick Calibration")
        #class variables
        self.ch1Val = 0
        self.ch1Min = 0
        self.ch1Max = 0

        self.ch2Val = 0
        self.ch2Min = 0
        self.ch2Max = 0

        self.ch3Val = 0
        self.ch3Min = 0
        self.ch3Max = 0

        self.ch1Active = False
        self.ch2Active = False
        self.ch3Active = False

        titlePtSize = 28

        #build layouts
        pagelayout = QVBoxLayout()
        button_layout = QVBoxLayout()
        channel_layout = QGridLayout()
        self.stacklayout = QStackedLayout()

        #stack layouts
        pagelayout.addLayout(channel_layout)
        channel_layout.addLayout(button_layout, 0, 1)
        pagelayout.addLayout(self.stacklayout)

        #add spacers
        space00 = QLabel(" ")
        space00.setFixedSize(50,400)
        channel_layout.addWidget(space00, 0, 0)

        space02 = QLabel(" ")
        space00.setFixedSize(50,400)
        channel_layout.addWidget(space02, 0, 2)

        space04 = QLabel(" ")
        space04.setFixedSize(50,400)
        channel_layout.addWidget(space04, 0, 4)

        space06 = QLabel(" ")
        space06.setFixedSize(50,400)
        channel_layout.addWidget(space06, 0, 6)

        space08 = QLabel(" ")
        space08.setFixedSize(50,400)
        channel_layout.addWidget(space08, 0, 8)

        space010 = QLabel(" ")
        space010.setFixedSize(50,400)
        channel_layout.addWidget(space010, 0, 10)



        #Start/stop buttons
        self.strtbtn = QPushButton("Start Stim")
        self.strtbtn.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.strtbtn.setFixedSize(100,100)
        button_layout.addWidget(self.strtbtn)

        self.stpbtn = QPushButton("Stop Stim")
        self.stpbtn.setStyleSheet("""
                 background-color: #B2060A;
                 """)
        self.stpbtn.setFixedSize(100,100)
        button_layout.addWidget(self.stpbtn)

#################
        #channel 1
        self.ch1 = QLabel("Channel 1")
        titlefont= self.ch1.font()
        titlefont.setPointSize(titlePtSize)
        self.ch1.setFont(titlefont)
        self.actBtn1 = QCheckBox("Active Channel")
        #sliders
        sldrLayout1 = QHBoxLayout()
        self.sld1 = QSlider()
        self.sld1.setFixedSize(50,400)
        self.sld1.setRange(0,100)


        #set buttons
        btnLayout1 = QVBoxLayout()
        #current Val box
        currentStim1 = QHBoxLayout()
        self.stimVal1 = QLabel("Current Stim Value:")
        self.stimVal1.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.ch1Stim = QLineEdit()
        self.ch1Stim.setFixedSize(40,20)
        self.up1 = QPushButton("+1")
        self.up1.setFixedSize(20,20)
        self.up1.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.down1 = QPushButton("-1")
        self.down1.setFixedSize(20,20)
        self.down1.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.addMax1 = QPushButton("Set Current Value as Max")
        self.addMax1.setStyleSheet("""
                 background-color: #E9741C;
                 """)

        self.addMin1 = QPushButton("Set Current Value as Min")
        self.addMin1.setStyleSheet("""
                 background-color: #1C90E9;
                 """)
        currentStim1.addWidget(self.stimVal1)
        currentStim1.addWidget(self.ch1Stim)
        currentStim1.addWidget(self.up1)
        currentStim1.addWidget(self.down1)
        #maximum box
        max1Layout = QHBoxLayout()
        self.max1 = QLineEdit()
        self.max1.setFixedSize(40,20)
        self.max1.setText("none")
        self.maxVal1 = QLabel("Stim maximum:")
        self.maxVal1.setStyleSheet("""
                 background-color: #E9741C;
                 """)
        max1Layout.addWidget(self.maxVal1)
        max1Layout.addWidget(self.max1)
        #minimum box
        min1Layout = QHBoxLayout()
        self.min1 = QLineEdit()
        self.min1.setFixedSize(40,20)
        self.min1.setText("none")
        self.minVal1 = QLabel("Stim minimum:")
        self.minVal1.setStyleSheet("""
                 background-color: #1C90E9;
                 """)
        min1Layout.addWidget(self.minVal1)
        min1Layout.addWidget(self.min1)

        #button layout build
        btnLayout1.addLayout(max1Layout)
        btnLayout1.addWidget(self.addMax1)
        btnLayout1.addLayout(currentStim1)
        btnLayout1.addWidget(self.addMin1)
        btnLayout1.addLayout(min1Layout)
        #sldrLayout build
        sldrLayout1.addLayout(btnLayout1)
        sldrLayout1.addWidget(self.sld1)

        #assemble channel layout
        ch1Layout = QVBoxLayout()
        ch1Layout.addWidget(self.ch1)
        ch1Layout.addWidget(self.actBtn1)
        ch1Layout.addLayout(sldrLayout1)
        channel_layout.addLayout(ch1Layout, 0, 5)

        #channel 1 actions
        self.sld1.valueChanged.connect(self.slider_val1) 
        self.addMax1.clicked.connect(self.max_set1)
        self.addMin1.clicked.connect(self.min_set1)
        self.min1.textChanged.connect(self.min1text_edited)
        self.max1.textChanged.connect(self.max1text_edited)
        self.ch1Stim.textChanged.connect(self.stimVal1_edited)
        self.up1.clicked.connect(self.up1_go)
        self.down1.clicked.connect(self.down1_go)
        self.actBtn1.stateChanged.connect(self.act1)

###############################
        #channel 2
        self.ch2 = QLabel("Channel 2")
        titlefont= self.ch2.font()
        titlefont.setPointSize(titlePtSize)
        self.ch2.setFont(titlefont)
        self.actBtn2 = QCheckBox("Active Channel")
        #sliders
        sldrLayout2 = QHBoxLayout()
        self.sld2 = QSlider()
        self.sld2.setFixedSize(50,400)
        self.sld2.setRange(0,100)


        #set buttons
        btnLayout2 = QVBoxLayout()
        #current Val box
        currentStim2 = QHBoxLayout()
        self.stimVal2 = QLabel("Current Stim Value:")
        self.stimVal2.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.ch2Stim = QLineEdit()
        self.ch2Stim.setFixedSize(40,20)
        self.up2 = QPushButton("+1")
        self.up2.setFixedSize(20,20)
        self.up2.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.down2 = QPushButton("-1")
        self.down2.setFixedSize(20,20)
        self.down2.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.addMax2 = QPushButton("Set Current Value as Max")
        self.addMax2.setStyleSheet("""
                 background-color: #E9741C;
                 """)

        self.addMin2 = QPushButton("Set Current Value as Min")
        self.addMin2.setStyleSheet("""
                 background-color: #1C90E9;
                 """)
        currentStim2.addWidget(self.stimVal2)
        currentStim2.addWidget(self.ch2Stim)
        currentStim2.addWidget(self.up2)
        currentStim2.addWidget(self.down2)
        #maximum box
        max2Layout = QHBoxLayout()
        self.max2 = QLineEdit()
        self.max2.setFixedSize(40,20)
        self.max2.setText("none")
        self.maxVal2 = QLabel("Stim maximum:")
        self.maxVal2.setStyleSheet("""
                 background-color: #E9741C;
                 """)
        max2Layout.addWidget(self.maxVal2)
        max2Layout.addWidget(self.max2)
        #minimum box
        min2Layout = QHBoxLayout()
        self.min2 = QLineEdit()
        self.min2.setFixedSize(40,20)
        self.min2.setText("none")
        self.minVal2 = QLabel("Stim minimum:")
        self.minVal2.setStyleSheet("""
                 background-color: #1C90E9;
                 """)
        min2Layout.addWidget(self.minVal2)
        min2Layout.addWidget(self.min2)

        #button layout build
        btnLayout2.addLayout(max2Layout)
        btnLayout2.addWidget(self.addMax2)
        btnLayout2.addLayout(currentStim2)
        btnLayout2.addWidget(self.addMin2)
        btnLayout2.addLayout(min2Layout)
        #sldrLayout build
        sldrLayout2.addLayout(btnLayout2)
        sldrLayout2.addWidget(self.sld2)

        #assemble channel layout
        ch2Layout = QVBoxLayout()
        ch2Layout.addWidget(self.ch2)
        ch2Layout.addWidget(self.actBtn2)
        ch2Layout.addLayout(sldrLayout2)
        channel_layout.addLayout(ch2Layout, 0, 7)

        #channel 2 actions
        self.sld2.valueChanged.connect(self.slider_val2) 
        self.addMax2.clicked.connect(self.max_set2)
        self.addMin2.clicked.connect(self.min_set2)
        self.min2.textChanged.connect(self.min2text_edited)
        self.max2.textChanged.connect(self.max2text_edited)
        self.ch2Stim.textChanged.connect(self.stimVal2_edited)
        self.up2.clicked.connect(self.up2_go)
        self.down2.clicked.connect(self.down2_go)
        self.actBtn2.stateChanged.connect(self.act2)

#################
        #channel 3
        self.ch3 = QLabel("Channel 3")
        titlefont= self.ch3.font()
        titlefont.setPointSize(titlePtSize)
        self.ch3.setFont(titlefont)
        self.actBtn3 = QCheckBox("Active Channel")
        #sliders
        sldrLayout3 = QHBoxLayout() 
        self.sld3 = QSlider() 
        self.sld3.setFixedSize(50,400)
        self.sld3.setRange(0,100)


        #set buttons
        btnLayout3 = QVBoxLayout()
        #current Val box
        currentStim3 = QHBoxLayout()
        self.stimVal3 = QLabel("Current Stim Value:")
        self.stimVal3.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.ch3Stim = QLineEdit()
        self.ch3Stim.setFixedSize(40,20)
        self.up3 = QPushButton("+1")
        self.up3.setFixedSize(20,20)
        self.up3.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.down3 = QPushButton("-1")
        self.down3.setFixedSize(20,20)
        self.down3.setStyleSheet("""
                 background-color: #80B71A;
                 """)
        self.addMax3 = QPushButton("Set Current Value as Max")
        self.addMax3.setStyleSheet("""
                 background-color: #E9741C;
                 """)

        self.addMin3 = QPushButton("Set Current Value as Min")
        self.addMin3.setStyleSheet("""
                 background-color: #1C90E9;
                 """)
        currentStim3.addWidget(self.stimVal3)
        currentStim3.addWidget(self.ch3Stim)
        currentStim3.addWidget(self.up3)
        currentStim3.addWidget(self.down3)
        #maximum box
        max3Layout = QHBoxLayout()
        self.max3 = QLineEdit()
        self.max3.setFixedSize(40,20)
        self.max3.setText("none")
        self.maxVal3 = QLabel("Stim maximum:")
        self.maxVal3.setStyleSheet("""
                 background-color: #E9741C;
                 """)
        max3Layout.addWidget(self.maxVal3)
        max3Layout.addWidget(self.max3)
        #minimum box
        min3Layout = QHBoxLayout()
        self.min3 = QLineEdit()
        self.min3.setFixedSize(40,20)
        self.min3.setText("none")
        self.minVal3 = QLabel("Stim minimum:")
        self.minVal3.setStyleSheet("""
                 background-color: #1C90E9;
                 """)
        min3Layout.addWidget(self.minVal3)
        min3Layout.addWidget(self.min3)

        #button layout build
        btnLayout3.addLayout(max3Layout)
        btnLayout3.addWidget(self.addMax3)
        btnLayout3.addLayout(currentStim3)
        btnLayout3.addWidget(self.addMin3)
        btnLayout3.addLayout(min3Layout)
        #sldrLayout build
        sldrLayout3.addLayout(btnLayout3)
        sldrLayout3.addWidget(self.sld3)

        #assemble channel layout
        ch3Layout = QVBoxLayout()
        ch3Layout.addWidget(self.ch3)
        ch3Layout.addWidget(self.actBtn3)
        ch3Layout.addLayout(sldrLayout3)
        channel_layout.addLayout(ch3Layout, 0, 9)

        #channel 3 actions
        self.sld3.valueChanged.connect(self.slider_val3) 
        self.addMax3.clicked.connect(self.max_set3)
        self.addMin3.clicked.connect(self.min_set3)
        self.min3.textChanged.connect(self.min3text_edited)
        self.max3.textChanged.connect(self.max3text_edited)
        self.ch3Stim.textChanged.connect(self.stimVal3_edited)
        self.up3.clicked.connect(self.up3_go)
        self.down3.clicked.connect(self.down3_go)
        self.actBtn3.stateChanged.connect(self.act3)


        #keep this!
        widget = QWidget()
        widget.setLayout(pagelayout)
        self.setCentralWidget(widget)

####################### ch 1 definitions
    def slider_val1(self, val):
            self.ch1Stim.setText(str(val))
            self.ch1Val = val

    def max_set1(self):
            self.ch1Max = self.ch1Val
            self.max1.setText(str(self.ch1Max))

    def min_set1(self): 
            self.ch1Min = self.ch1Val
            self.min1.setText(str(self.ch1Min))

    def min1text_edited(self, text):
            self.ch1Min = int(text)

    def max1text_edited(self, text):
            self.ch1Max = int(text)

    def stimVal1_edited(self, text):
            self.sld1.setValue(int(text))

    def up1_go(self):
            self.ch1Val = self.ch1Val + 1
            self.sld1.setValue(self.ch1Val)

    def down1_go(self):
            self.ch1Val = self.ch1Val - 1
            self.sld1.setValue(self.ch1Val)

    def act1(self, s):
            if (s == 2):
                self.channel1Active = True
            else:
                self.channel1Active = False


####################ch2 definitions
    def slider_val2(self, val):
            self.ch2Stim.setText(str(val))
            self.ch2Val = val

    def max_set2(self):
            self.ch2Max = self.ch2Val
            self.max2.setText(str(self.ch2Max))

    def min_set2(self): 
            self.ch2Min = self.ch2Val
            self.min2.setText(str(self.ch2Min))

    def min2text_edited(self, text):
            self.ch2Min = int(text)

    def max2text_edited(self, text):
            self.ch2Max = int(text)

    def stimVal2_edited(self, text):
            self.sld2.setValue(int(text))

    def up2_go(self):
            self.ch2Val = self.ch2Val + 1
            self.sld2.setValue(self.ch2Val)

    def down2_go(self):
            self.ch2Val = self.ch2Val - 1
            self.sld2.setValue(self.ch2Val)

    def act2(self, s):
            if (s == 2):
                self.channel2Active = True
            else:
                self.channel2Active = False

####################ch3 definitions
    def slider_val3(self, val):
            self.ch3Stim.setText(str(val))
            self.ch3Val = val

    def max_set3(self):
            self.ch3Max = self.ch3Val
            self.max3.setText(str(self.ch3Max))

    def min_set3(self): 
            self.ch3Min = self.ch3Val
            self.min3.setText(str(self.ch3Min))

    def min3text_edited(self, text):
            self.ch3Min = int(text)

    def max3text_edited(self, text):
            self.ch3Max = int(text)

    def stimVal3_edited(self, text):
            self.sld3.setValue(int(text))

    def up3_go(self):
            self.ch3Val = self.ch3Val + 1
            self.sld3.setValue(self.ch3Val)

    def down3_go(self):
            self.ch3Val = self.ch3Val - 1
            self.sld3.setValue(self.ch3Val)

    def act3(self, s):
            if (s == 2):
                self.channel3Active = True
            else:
                self.channel3Active = False

#execute instructions
app = QApplication(sys.argv)
window = MainWindow()
window.show()
app.exec()
