{{
┌─────────────────────────────────────────────────┐
│ JTAGulator                                      │
│                                                 │
│ Author: Joe Grand                               │                     
│ Copyright (c) 2013 Grand Idea Studio, Inc.      │
│ Web: http://www.grandideastudio.com             │
│                                                 │
│ Distributed under a Creative Commons            │
│ Attribution 3.0 United States license           │
│ http://creativecommons.org/licenses/by/3.0/us/  │
└─────────────────────────────────────────────────┘

Program Description:

The JTAGulator is a tool to assist in identifying on-chip debugging (OCD) and/or
programming connections from test points, vias, or component pads on a target
piece of hardware.

Refer to the project page for more details:

http://www.grandideastudio.com/portfolio/jtagulator/

Each interface object contains the low-level routines and operational details
for that particular on-chip debugging interface. This keeps the main JTAGulator
object a bit cleaner. 

Command listing is available in the DAT section at the end of this file.

}}


CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000           ' 5 MHz clock * 16x PLL = 80 MHz system clock speed 
  _stack   = 100                 ' Ensure we have this minimum stack space available        

  ' Serial terminal
  ' Control characters
  NL = 13  ''NL: New Line
  LF = 10  ''LF: Line Feed
  
  ' JTAGulator I/O pin definitions
  PROP_SDA    = 29
  PROP_SCL    = 28  
  LED_R       = 27   ' Bi-color Red/Green LED, common cathode
  LED_G       = 26
  DAC_OUT     = 25   ' PWM output for DAC
  TXS_OE      = 24   ' Output Enable for TXS0108E level translators

  ' JTAG/IEEE 1149.1
  MIN_CHAN    = 4    ' Minimum number of pins/channels required for JTAG identification
  MAX_CHAN    = 24   ' Maximum number of pins/channels the JTAGulator hardware provides (P23..P0)
  MAX_NUM     = 32   ' Maximum number of devices allowed in a single JTAG chain

  
VAR                   ' Globally accessible variables 
  long vTarget        ' Target system voltage (for example, 18 = 1.8V)
  
  long jTDI           ' JTAG pins (must stay in this order)
  long jTDO
  long jTCK
  long jTMS
  long jNUM           ' Number of devices in JTAG chain         
  

OBJ
  ser           : "Parallax Serial Terminal"            ' Serial communication (included w/ Parallax Propeller Tool)
  rr            : "RealRandom"                          ' Random number generation (Chip Gracey, http://obex.parallax.com/object/498) 
  jtag          : "PropJTAG"                            ' JTAG/IEEE 1149.1 low-level functions


PUB main | cmd, bPattern, value 
  SystemInit
  ser.Str(@InitHeader)          ' Display header; uses string in DAT section.

  ' Start command receive/process cycle
  repeat
    TXSDisable                     ' Disable level shifter outputs (high-impedance)
    LEDGreen                       ' Set status indicator to show that we're ready
    ser.Str(String(NL, LF, ":"))   ' Display command prompt
    cmd := ser.CharIn              ' Wait here to receive a byte
    LEDRed                         ' Set status indicator to show that we're processing a command

    case cmd
      "I", "i":                 ' Identify JTAG pinout (IDCODE Scan)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          IDCODE_Scan

      "B", "b":                 ' Identify JTAG pinout (BYPASS Scan)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          BYPASS_Scan
          
      "D", "d":                 ' Get JTAG Device IDs (Pinout already known)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          IDCODE_Known

      "T", "t":                 ' Test BYPASS (TDI to TDO) (Pinout already known)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          BYPASS_Known
                        
      "V", "v":                 ' Set target system voltage
        Set_Target_Voltage
        
      "R", "r":                 ' Read all channels (input)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          Read_IO_Pins

      "W", "w":                 ' Write all channels (output)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          Write_IO_Pins
      
      "H", "h":                 ' Display list of available commands
        ser.Str(@CommandList)      ' Uses string in DAT section.
                
      other:                    ' Unknown command    
        ser.Str(String(NL, LF, "?"))


PRI IDCODE_Scan | value, num_chan    ' Identify JTAG pinout (IDCODE Scan)
  num_chan := Get_Channels      ' Get the number of channels to use
  if (num_chan == -1)           ' If value is out of range, skip function
    return

  Display_Permutations(num_chan, 3)  ' TDO, TCK, TMS

  ser.Str(String(NL, LF, "Press spacebar to begin (any other key to abort)..."))
  if (ser.CharIn <> " ")
    ser.Str(String(NL, LF, "IDCODE scan aborted!"))
    return

  ser.Str(String(NL, LF, "JTAGulating! Press any key to abort...", NL, LF))
  TXSEnable     ' Enable level shifter outputs

  ' We assume the IDCODE is the default DR after reset
  jTDI := PROP_SDA    ' TDI isn't used when we're just shifting data from the DR. Set TDI to a temporary pin so it doesn't interfere with enumeration.
  repeat jTDO from 0 to (num_chan-1)   ' For every possible pin combination (except TDI)...
    repeat jTCK from 0 to (num_chan-1)
      if (jTCK == jTDO)
        next
      repeat jTMS from 0 to (num_chan-1)
        if (jTMS == jTCK) or (jTMS == jTDO)
          next

        if (ser.RxCount)  ' Abort scan if any key is pressed
          ser.RxFlush
          ser.Str(String(NL, LF, "IDCODE scan aborted!"))
          return

        Set_Pins_High(num_chan)              ' Set currently selected channels to output HIGH
        jtag.Config(jTDI, jTDO, jTCK, jTMS)  ' Configure JTAG pins
        jtag.Get_Device_IDs(1, @value)       ' Try to get Device ID by reading the DR      
        if (value <> -1) and (value & 1)     ' Ignore if received Device ID is 0xFFFFFFFF or if bit 0 != 1
          Display_JTAG_Pins                    ' Display current JTAG pinout

  longfill(@jTDI, 0, 4) ' Clear JTAG pinout 
  ser.Str(String(NL, LF, "IDCODE scan complete!"))


PRI BYPASS_Scan | value, num_chan, bPattern      ' Identify JTAG pinout (BYPASS Scan)
  num_chan := Get_Channels      ' Get the number of channels to use
  if (num_chan == -1)           ' If value is out of range, skip function
    return

  Display_Permutations(num_chan, 4)  ' TDI, TDO, TCK, TMS
    
  ser.Str(String(NL, LF, "Press spacebar to begin (any other key to abort)..."))
  if (ser.CharIn <> " ")
    ser.Str(String(NL, LF, "BYPASS scan aborted!"))
    return

  ser.Str(String(NL, LF, "JTAGulating! Press any key to abort...", NL, LF))
  TXSEnable     ' Enable level shifter outputs

  ' Pin enumeration logic based on JTAGenum (http://deadhacker.com/2010/02/03/jtag-enumeration/)
  repeat jTDI from 0 to (num_chan-1)        ' For every possible pin combination... 
    repeat jTDO from 0 to (num_chan-1)
      if (jTDO == jTDI)  ' Ensure each pin number is unique
        next
      repeat jTCK from 0 to (num_chan-1)
        if (jTCK == jTDO) or (jTCK == jTDI)
          next
        repeat jTMS from 0 to (num_chan-1)
          if (jTMS == jTCK) or (jTMS == jTDO) or (jTMS == jTDI)
            next
            
          if (ser.RxCount)  ' Abort scan if any key is pressed
            ser.RxFlush
            ser.Str(String(NL, LF, "BYPASS scan aborted!"))
            return

          Set_Pins_High(num_chan)                  ' Set currently selected channels to output HIGH
          jtag.Config(jTDI, jTDO, jTCK, jTMS)      ' Configure JTAG pins
          value := jtag.Detect_Devices
          if (value)
            ser.Str(String(NL, LF, "Number of devices detected: "))
            ser.Dec(value)
            Display_JTAG_Pins                      ' Display current JTAG pinout         

  longfill(@jTDI, 0, 4) ' Clear JTAG pinout        
  ser.Str(String(NL, LF, "BYPASS scan complete!"))

  
PRI IDCODE_Known | value, id[MAX_NUM], i        ' Get JTAG Device IDs (Pinout already known)  
  if (Set_JTAG == -1)     ' Ask user for the known JTAG pinout
    return                ' Abort if error
    
  if (Set_NUM == -1)      ' Ask user for the number of devices in JTAG chain
    return                ' Abort if error 

  TXSEnable                               ' Enable level shifter outputs
  Set_Pins_High(MAX_CHAN)                 ' Set all channels to output HIGH
  jtag.Config(jTDI, jTDO, jTCK, jTMS)     ' Configure JTAG pins 
  jtag.Get_Device_IDs(jNUM, @id)          ' We assume the IDCODE is the default DR after reset
  repeat i from 0 to (jNUM-1)             ' For each device in the chain...
    value := id[i]
    if (value <> -1) and (value & 1)        ' Ignore if received Device ID is 0xFFFFFFFF or if bit 0 != 1
      if (jNUM == 1)
        Display_Device_ID(value, 0)
      else
        Display_Device_ID(value, i + 1)       ' Display Device ID of current device    
              
  ser.Str(String(NL, LF, "IDCODE listing complete!"))


PRI BYPASS_Known | dataIn, dataOut   ' Test BYPASS (TDI to TDO) (Pinout already known)
  if (Set_JTAG == -1)     ' Ask user for the known JTAG pinout
    return                ' Abort if error
    
  if (Set_NUM == -1)      ' Ask user for the number of devices in JTAG chain
    return                ' Abort if error
    
  TXSEnable                                   ' Enable level shifter outputs
  Set_Pins_High(MAX_CHAN)                     ' Set all channels to output HIGH
  jtag.Config(jTDI, jTDO, jTCK, jTMS)         ' Configure JTAG pins

  dataIn := rr.random                         ' Get 32-bit random number to use as the BYPASS pattern
  dataOut := jtag.Bypass_Test(jNUM, dataIn)   ' Run the BYPASS instruction 

  ' Display input/output data and check if they match
  ser.Str(String(NL, LF, "Pattern in to TDI:    "))
  ser.Bin(dataIn, 32)   ' Display value as binary characters (0/1)

  ser.Str(String(NL, LF, "Pattern out from TDO: "))
  ser.Bin(dataOut, 32)  ' Display value as binary characters (0/1)

  if (dataIn == dataOut)
    ser.Str(String(NL, LF, "Match!"))
  else
    ser.Str(String(NL, LF, "No Match!"))
    

PRI Set_Target_Voltage | value
  ser.Str(String(NL, LF, "Current target voltage: "))
  Display_Target_Voltage

  ser.Str(String(NL, LF, "Enter new target voltage (1.2 - 3.3): "))
  value := ser.DecIn                            ' Receive carriage return terminated string of characters representing a decimal value
  if (value < 12) or (value > 33)
    ser.Str(String(LF, "Out of range!"))
  else
    vTarget := value
    DACOutput(VoltageTable[vTarget - 12])       ' Look up value that corresponds to the actual desired voltage and set DAC output
    ser.Str(String(LF, "New target voltage set!"))


PRI Read_IO_Pins | value, count              ' Read all channels (input)  
  ser.Char(ser#NL)
  
  TXSEnable               ' Enable level shifter outputs
  dira[23..0]~            ' Set P23-P0 as inputs
  value := ina[23..0]     ' Read all channels

  ser.Str(String(NL, LF, "CH23..CH0: "))
  
  ' Display value as binary characters (0/1)
  repeat count from 16 to 0 step 8
    ser.Bin(value >> count, 8)
    ser.Char(" ")
 
  ' Display value as hexadecimal
  ser.Str(String(" ("))
  ser.Hex(value, 6)
  ser.Str(String(")"))    

  
PRI Write_IO_Pins : err | value, count       ' Write all channels (output)
  ser.Str(String(NL, LF, "Enter value to output (in hex): "))
  value := ser.HexIn      ' Receive carriage return terminated string of characters representing a hexadecimal value

  if (value & $ff000000)
    ser.Str(String(LF, "Out of range!"))
    return -1
      
  TXSEnable               ' Enable level shifter outputs
  dira[23..0]~~           ' Set P23-P0 as outputs
  outa[23..0] := value    ' Write value to output
  
  ser.Str(String(NL, LF, "CH23..CH0 set to: "))
  repeat count from 16 to 0 step 8
    ser.Bin(value >> count, 8)
    ser.Char(" ")
    
  ' Display value as hexadecimal
  ser.Str(String(" ("))
  ser.Hex(value, 6)
  ser.Str(String(")"))    

  ser.Str(String(NL, LF, "Press any key when done..."))
  ser.CharIn       ' Wait for any key to be pressed before finishing routine (and disabling level translators)

    
PRI Get_Channels : value | buf
  ser.Str(String(NL, LF, "Enter number of channels to use (4 - 24): "))
  value := ser.DecIn                              ' Receive carriage return terminated string of characters representing a decimal value
  if (value < MIN_CHAN) or (value > MAX_CHAN)
    ser.Str(String(LF, "Out of range!"))
    value := -1
  else
    ser.Str(String(NL, LF, "Ensure connections are on CH"))
    ser.Dec(value-1)
    ser.Str(String("..CH0."))


PRI Set_NUM  : err | value          ' Set the number of devices in chain
  ser.Str(String(NL, LF, "Enter number of devices in JTAG chain ["))
  ser.Dec(jNUM)               ' Display current value
  ser.Str(String("]: "))
  value := Get_Decimal_Pin    ' Get new value from user
  if (value == -1)            ' If carriage return was pressed...      
    value := jNUM               ' Keep current setting
  if (value < 1) or (value > MAX_NUM)   ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  jNUM := value
  

PRI Set_JTAG : err | xtdi, xtdo, xtck, xtms, buf, c    ' Set JTAG configuration to known values
  ser.Str(String(NL, LF, "Enter new TDI pin ["))
  ser.Dec(jTDI)               ' Display current value
  ser.Str(String("]: "))
  xtdi := Get_Decimal_Pin     ' Get new value from user
  if (xtdi == -1)             ' If carriage return was pressed...      
    xtdi := jTDI                ' Keep current setting
  if (xtdi < 0) or (xtdi > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new TDO pin ["))
  ser.Dec(jTDO)               ' Display current value
  ser.Str(String("]: "))
  xtdo := Get_Decimal_Pin     ' Get new value from user
  if (xtdo == -1)             ' If carriage return was pressed...      
    xtdo := jTDO                ' Keep current setting
  if (xtdo < 0) or (xtdo > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new TCK pin ["))
  ser.Dec(jTCK)               ' Display current value
  ser.Str(String("]: "))
  xtck := Get_Decimal_Pin     ' Get new value from user
  if (xtck == -1)             ' If carriage return was pressed...      
    xtck := jTCK                ' Keep current setting
  if (xtck < 0) or (xtck > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new TMS pin ["))
  ser.Dec(jTMS)               ' Display current value
  ser.Str(String("]: "))
  xtms := Get_Decimal_Pin     ' Get new value from user
  if (xtms == -1)             ' If carriage return was pressed...      
    xtms := jTMS                ' Keep current setting
  if (xtms < 0) or (xtms > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1       

  ' Make sure that each pin number is unique
  ' Set bit in a long corresponding to each pin number
  buf := 0
  buf |= (1 << xtdi)
  buf |= (1 << xtdo)
  buf |= (1 << xtck)
  buf |= (1 << xtms)
  
  ' Count the number of bits that are set in the long
  c := 0
  repeat 32
    c += (buf & 1)
    buf >>= 1

  if (c <> 4)         ' If there are not exactly 4 bits set, then we have a collision
    ser.Str(String(LF, "Pin numbers must be unique!"))
    return -1
  else                ' If there are no collisions, update the pinout globals with the new values
    jTDI := xtdi      
    jTDO := xtdo
    jTCK := xtck
    jTMS := xtms


PRI Set_Pins_High(num) | i     ' Set currently selected channels to output HIGH during a scan
  repeat i from 0 to (num-1)   ' From CH0..CH(num-1)
    dira[i] := 1
    outa[i] := 1


PRI Get_Decimal_Pin : value | buf       ' Get a pin number from the user (including number 0, which prevents us from using standard Parallax Serial Terminal routines)
  if ((buf := ser.CharIn) == NL)        ' If the first byte we receive is a carriage return...
    value := -1                               ' Then exit
  else                                  ' Otherwise, the first byte may be valid
    value := (buf - "0")                      ' Convert it into a decimal value
    repeat while ((buf := ser.CharIn) <> NL)  ' Get subsequent bytes until a carriage return is received
      value *= 10
      value += (buf - "0")                       ' Keep converting into a decimal value...


PRI Display_Target_Voltage
  if (vTarget == -1)
    ser.Str(String("Undefined"))
  else
    ser.Dec(vTarget / 10)          ' Display vTarget as an x.y value
    ser.Char(".")
    ser.Dec(vTarget // 10)


PRI Display_Permutations(n, r) | value, i
{{  http://www.mathsisfun.com/combinatorics/combinations-permutations-calculator.html

    Order important, no repetition
    Total pins (n)
    Number of pins needed (r)
    Number of permutations: n! / (n-r)!
}}

  ser.Str(String(NL, LF, "Possible permutations: "))

  ' Thanks to Rednaxela of #tymkrs for the optimized calculation
  value := 1
  repeat i from (n - r + 1) to n
    value *= i    

  ser.Dec(value)


PRI Display_JTAG_Pins
  ser.Str(String(NL, LF, "TDI: "))
  if (jTDI => MAX_CHAN)     ' TDI isn't used during an IDCODE Scan (we're not shifting any data into the target), so it can't be determined
    ser.Str(String("N/A"))  
  else
    ser.Dec(jTDI)
  ser.Str(String(NL, LF, "TDO: "))
  ser.Dec(jTDO)
  ser.Str(String(NL, LF, "TCK: "))
  ser.Dec(jTCK)
  ser.Str(String(NL, LF, "TMS: "))
  ser.Dec(jTMS)
  ser.Str(String(NL, LF))
  

PRI Display_Device_ID(value, num)
  ser.Str(String(NL, LF, "Device ID"))
  if (num > 0)
    ser.Str(String(" #"))
    ser.Dec(num)
  ser.Str(String(": "))
  
  ' Display value as binary characters (0/1) based on IEEE Std. 1149.1 2001 Device Identification Register structure  
  ser.Bin(value >> 28, 4)       ' Version
  ser.Char(" ")
  ser.Bin(value >> 12, 16)      ' Part Number
  ser.Char(" ")  
  ser.Bin(value >> 1, 11)       ' Manufacturer Identity
  ser.Char(" ")
  ser.Bin(value, 1)             ' Fixed (should always be 1)

  ' Display value as hexadecimal
  ser.Str(String(" ("))
  ser.Hex(value, 8)
  ser.Str(String(")"))  


PRI Display_Voltage_Error
  ser.Str(String(NL, LF, "Target voltage must be defined!"))

     
PRI SystemInit
  ' Set direction of I/O pins
  ' Output
  dira[TXS_OE] := 1
  dira[LED_R]  := 1        
  dira[LED_G]  := 1
   
  ' Set I/O pins to the proper initialization values
  TXSDisable      ' Disable level shifter outputs (high-impedance)
  LedYellow       ' Yellow = system initialization

  ' Set up PWM channel for DAC output
  ' Based on Andy Lindsay's PropBOE D/A Converter (http://learn.parallax.com/node/107)
  ctra[30..26]  := %00110       ' Set CTRMODE to PWM/duty cycle (single ended) mode
  ctra[5..0]    := DAC_OUT      ' Set APIN to desired pin
  dira[DAC_OUT] := 1            ' Set pin as output
  DACOutput(0)                  ' DAC output off 

  vTarget := -1                 ' Target voltage is undefined 
  rr.start                      ' Start RealRandom cog
  ser.Start(115_200)            ' Start serial communications


PRI DACOutput(dacval)
  spr[10] := dacval * 16_777_216    ' Set counter A frequency (scale = 2³²÷ 256)  

    
PRI TXSEnable
  dira[23..0]~                      ' Set P23-P0 as inputs to avoid contention when driver is enabled. Pin directions will be configured by other functions as needed.
  outa[TXS_OE] := 1
  waitcnt(clkfreq / 100_000 + cnt)  ' 10uS delay (must wait > 200nS for TXS0108E one-shot circuitry to become operational)


PRI TXSDisable
  outa[TXS_OE] := 0

    
PRI LedOff
  outa[LED_R] := 0 
  outa[LED_G] := 0

  
PRI LedGreen
  outa[LED_R] := 0 
  outa[LED_G] := 1

  
PRI LedRed
  outa[LED_R] := 1 
  outa[LED_G] := 0

  
PRI LedYellow
  outa[LED_R] := 1 
  outa[LED_G] := 1

               
DAT
InitHeader    byte NL, LF, "JTAGulator 1.0.1", NL, LF
              byte "Designed by Joe Grand [joe@grandideastudio.com]", NL, LF, 0

CommandList   byte NL, LF, "JTAG Commands:", NL, LF
              byte "I   Identify JTAG pinout (IDCODE Scan)", NL, LF
              byte "B   Identify JTAG pinout (BYPASS Scan)", NL, LF
              byte "D   Get Device ID(s)", NL, LF
              byte "T   Test BYPASS (TDI to TDO)", NL, LF
              byte NL, LF, "General Commands:", NL, LF
              byte "V   Set target system voltage (1.2V to 3.3V)", NL, LF
              byte "R   Read all channels (input)", NL, LF  
              byte "W   Write all channels (output)", NL, LF
              byte "H   Print available commands", 0

' Look-up table to correlate actual voltage (1.2V to 3.3V) to DAC value
' Full DAC range is 0 to 3.3V @ 256 steps = 12.89mV/step
'                  1.2  1.3  1.4  1.5  1.6  1.7  1.8  1.9  2.0  2.1  2.2  2.3  2.4  2.5  2.6  2.7  2.8  2.9  3.0  3.1  3.2  3.3           
VoltageTable  byte  93, 101, 109, 116, 124, 132, 140, 147, 155, 163, 171, 179, 186, 194, 202, 210, 217, 225, 233, 241, 248, 255 

      