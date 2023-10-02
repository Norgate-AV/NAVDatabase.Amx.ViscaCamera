MODULE_NAME='mViscaCamera'      (
                                    dev vdvObject,
                                    dev vdvControl
                                )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.ArrayUtils.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT
constant long TL_DRIVE = 1

constant integer REQUIRED_POWER_ON    = 1
constant integer REQUIRED_POWER_OFF    = 2

constant integer ACTUAL_POWER_ON    = 1
constant integer ACTUAL_POWER_OFF    = 2


constant integer GET_POWER = 1
constant integer GET_PAN    = 2
constant integer GET_ZOOM    = 3

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE
volatile long ltDrive[] = { 500 }
volatile integer iLoop

volatile char cUnitID[]    = '1'

volatile integer iIsInitialized

volatile integer iID

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile integer iCommandLockOut

volatile integer iRequiredPower
volatile integer iActualPower

volatile integer iPollSequence = GET_POWER

volatile integer iCommunicating


volatile integer iTiltSpeed    = 5
volatile integer iPanSpeed    = 5
volatile integer iZoomSpeed    = 2


volatile integer iLastPTZ

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)
define_function SendCommand(char cParam[]) {
    NAVLog("'Command to ',NAVStringSurroundWith(NAVDeviceToString(vdvControl), '[', ']'),': [',cParam,']'")
    send_command vdvControl,"cParam"
}

define_function BuildCommand(char cHeader[], char cCmd[]) {
    if (length_array(cCmd)) {
    SendCommand("cHeader,'-<',itoa(iID),'|',cCmd,'>'")
    }else {
    SendCommand("cHeader,'-<',itoa(iID),'>'")
    }
}

define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]
    iSemaphore = true
    while (length_array(cRxBuffer) && NAVContains(cRxBuffer,'>')) {
    cTemp = remove_string(cRxBuffer,"'>'",1)
    if (length_array(cTemp)) {
        NAVLog("'Parsing String From ',NAVStringSurroundWith(NAVDeviceToString(vdvControl), '[', ']'),': [',cTemp,']'")
        if (NAVContains(cRxBuffer, cTemp)) { cRxBuffer = "''" }
        select {
        active (NAVStartsWith(cTemp,'REGISTER')): {
            iID = atoi(NAVGetStringBetween(cTemp,'<','>'))
            if (iID) { BuildCommand('REGISTER','') }
            NAVLog("'VISCA_REGISTER_REQUESTED<',itoa(iID),'>'")
            NAVLog("'VISCA_REGISTER<',itoa(iID),'>'")
        }
        active (NAVStartsWith(cTemp,'INIT')): {
            //if (cUnitGroup == '*' || cUnitID == '*') {
            //if (!iIsInitialized) {
                //iIsInitialized = true
                //BuildCommand('INIT_DONE','')
            //}
           // }else {
            iIsInitialized = false
            iPollSequence = GET_POWER
            GetInitialized()
            NAVLog("'VISCA_INIT_REQUESTED<',itoa(iID),'>'")

            //}
        }
        active (NAVStartsWith(cTemp,'START_POLLING')): {
            timeline_create(TL_DRIVE,ltDrive,length_array(ltDrive),TIMELINE_ABSOLUTE,TIMELINE_REPEAT)
        }
        active (NAVStartsWith(cTemp,'RESPONSE_MSG')): {
            stack_var char cResponseRequestMess[NAV_MAX_BUFFER]
            stack_var char cResponseMess[NAV_MAX_BUFFER]
            iCommunicating = true
            //NAVLog("'RESPONCE_MSG_RECEIVED<',itoa(iID),'>: ',cTemp")
            TimeOut()
            cResponseRequestMess = NAVGetStringBetween(cTemp,'<','|')
            cResponseMess = NAVGetStringBetween(cTemp,'|','>')
            //NAVLog("'VISCA_GOT_RESPONSE<',itoa(iID),'>','<',cResponseMess,'>'")
            //BuildCommand('RESPONSE_OK',cResponseRequestMess)
            select {
            active (NAVContains(cResponseMess,"atoi(cUnitID) + $8F,$50")): {
                //NAVLog("'VISCA_GOT_INIT_RESPONSE<',itoa(iID),'>'")
                remove_string(cResponseMess,"atoi(cUnitID) + $8F,$50",1)
                switch (iPollSequence) {
                case GET_POWER: {
                    switch (cResponseMess[1]) {
                    case $02: { iActualPower = ACTUAL_POWER_ON }
                    case $03: { iActualPower = ACTUAL_POWER_OFF }
                    }

                    if (!iIsInitialized) {
                    iIsInitialized = true
                    BuildCommand('INIT_DONE','')
                    NAVLog("'VISCA_INIT_DONE<',itoa(iID),'>'")
                    }

                    //iPollSequence = GET_PAN
                }
                case GET_PAN: {
                    iPollSequence = GET_ZOOM
                }
                case GET_ZOOM: {
                    /*
                    if (!iIsInitialized) {
                    iIsInitialized = true
                    BuildCommand('INIT_DONE','')
                    NAVLog("'VISCA_INIT_DONE<',itoa(iID),'>'")
                    }
                    */

                    iPollSequence = GET_POWER
                }
                }
            }
            }
        }
        }
    }
    }

    iSemaphore = false
}

define_function GetInitialized() {
    //NAVLog("'VISCA_GETTING_INITIALIZED<',itoa(iID),'>'")
    SendQuery(GET_POWER)
    //SendQuery(GET_PAN)
    //SendQuery(GET_ZOOM)
}

define_function char[NAV_MAX_BUFFER] BuildString(char cByte1[], char cByte2[], char cByte3[], char cByte4[], char cByte5[], char cByte6[], char cByte7[], char cByte8[]) {
    stack_var char cTemp[8]
    if (length_array(cByte1)) { cTemp = "cTemp,cByte1" }
    if (length_array(cByte2)) { cTemp = "cTemp,cByte2" }
    if (length_array(cByte3)) { cTemp = "cTemp,cByte3" }
    if (length_array(cByte4)) { cTemp = "cTemp,cByte4" }
    if (length_array(cByte5)) { cTemp = "cTemp,cByte5" }
    if (length_array(cByte6)) { cTemp = "cTemp,cByte6" }
    if (length_array(cByte7)) { cTemp = "cTemp,cByte7" }
    if (length_array(cByte8)) { cTemp = "cTemp,cByte8" }
    return cTemp
}

define_function SendQuery(integer iParam) {
    switch (iParam) {
    case GET_POWER: {
        BuildCommand('POLL_MSG',BuildString("atoi(cUnitID) + $80","$09","$04","$00",'','','',''))
        //NAVLog("'VISCA_SENDING_INIT_COMMAND<',itoa(iID),'>'")
    }
    case GET_PAN: { BuildCommand('POLL_MSG',BuildString("atoi(cUnitID) + $80","$09","$06","$12",'','','','')) }
    case GET_ZOOM: { BuildCommand('POLL_MSG',BuildString("atoi(cUnitID) + $80","$09","$04","$47",'','','','')) }
    }
}

define_function TimeOut() {
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' { iCommunicating = false }
}

define_function SetPower(integer iParam) {
    switch (iParam) {
    case REQUIRED_POWER_ON: { BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$00","$02",'','','')) }
    case REQUIRED_POWER_OFF: { BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$00","$03",'','','')) }
    }
}

define_function Drive() {
    iLoop++
    switch (iLoop) {
    case 1:
    case 11:
    case 21:
    case 31: { SendQuery(iPollSequence); return }
    case 41: { iLoop = 0; return }
    default: {
        if (iCommandLockOut) { return }
        if (iRequiredPower && (iRequiredPower == iActualPower)) { iRequiredPower = 0; return }

        if (iRequiredPower && (iRequiredPower <> iActualPower) && iCommunicating) {
        SetPower(iRequiredPower)
        iCommandLockOut = true
        wait 150 iCommandLockOut = false
        iPollSequence = GET_POWER
        return
        }
    }
    }
}

define_function RecallLastPTZ(integer iParam) {
    switch (iLastPTZ) {
    case 1: {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$03","$01"))
    }
    case 2: {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$03","$02"))
    }
    case 3: {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$01","$03"))
    }
    case 4: {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$02","$03"))
    }
    case 5: {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$07","$20 + iZoomSpeed",'','',''))
    }
    case 6: {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$07","$30 + iZoomSpeed",'','',''))
    }
    }
}

(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer vdvControl,cRxBuffer

    set_virtual_channel_count(vdvObject, 1024)
    set_virtual_level_count(vdvObject, 30)
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT
data_event[vdvControl] {
    online: {
    }
    string: {
    if (!iSemaphore) {
        Process()
    }
    }
}

data_event[vdvObject] {
    command: {
        stack_var char cCmdHeader[NAV_MAX_CHARS]
    stack_var char cCmdParam[2][NAV_MAX_CHARS]

    NAVLog("'Command from ',NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'),': [',data.text,']'")
    cCmdHeader = DuetParseCmdHeader(data.text)
    cCmdParam[1] = DuetParseCmdParam(data.text)
    cCmdParam[2] = DuetParseCmdParam(data.text)
    switch (cCmdHeader) {
        case 'PROPERTY': {
        switch (cCmdParam[1]) {
            case 'UNIT_ID': {
            cUnitID = cCmdParam[2]
            }
        }
        }
        case 'POWER': {
        switch (cCmdParam[1]) {
            case 'ON': {
            iRequiredPower = REQUIRED_POWER_ON; Drive()
            }
            case 'OFF': {
            iRequiredPower = REQUIRED_POWER_OFF; Drive()
            }
        }
        }
        case 'PRESET': {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$3F","$02","atoi(cCmdParam[1])","$FF",""))
        }
        case 'PRESETSAVE': {
        BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$3F","$01","atoi(cCmdParam[1])","$FF",""))
        }
    }
    }
}

define_event channel_event[vdvObject,0] {
    on: {
        switch (channel.channel) {
        case PWR_ON: {
            iRequiredPower = REQUIRED_POWER_ON; Drive()
        }
        case PWR_OFF: {
            iRequiredPower = REQUIRED_POWER_OFF; Drive()
        }
        case TILT_UP: {
            iLastPTZ = 1
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$03","$01"))
        }
        case TILT_DN: {
            iLastPTZ = 2
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$03","$02"))
        }
        case PAN_LT: {
            iLastPTZ = 3
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$01","$03"))
        }
        case PAN_RT: {
            iLastPTZ = 4
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$02","$03"))
        }
        case ZOOM_IN: {
            iLastPTZ = 5
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$07","$20 + iZoomSpeed",'','',''))
        }
        case ZOOM_OUT: {
            iLastPTZ = 6
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$07","$30 + iZoomSpeed",'','',''))
        }
        case NAV_PRESET_1:
        case NAV_PRESET_2:
        case NAV_PRESET_3:
        case NAV_PRESET_4:
        case NAV_PRESET_5:
        case NAV_PRESET_6:
        case NAV_PRESET_7:
        case NAV_PRESET_8: {
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$3F","$02","NAVFindInArrayINTEGER(NAV_PRESET, channel.channel)","$FF",""))
        }
        }
    }
    off: {
        switch (channel.channel) {
        case TILT_UP:
        case TILT_DN:
        case PAN_LT:
        case PAN_RT: {
            iLastPTZ = 0
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$06","$01","iTiltSpeed","iPanSpeed","$03","$03"))
        }
        case ZOOM_IN:
        case ZOOM_OUT: {
            iLastPTZ = 0
            BuildCommand('COMMAND_MSG',BuildString("atoi(cUnitID) + $80","$01","$04","$07","$00",'','',''))
        }
        }
    }
}

level_event[vdvObject,TILT_SPEED_LVL] {
    iTiltSpeed = level.value
    NAVLog("'VISCA_TILT_SPEED_CHANGE<',itoa(iID),'>TILT_SPEED<',itoa(iTiltSpeed),'>'")
    if (iLastPTZ) {
    RecallLastPTZ(iLastPTZ)
    }
}

level_event[vdvObject,PAN_SPEED_LVL] {
    iPanSpeed = level.value
    NAVLog("'VISCA_PAN_SPEED_CHANGE<',itoa(iID),'>PAN_SPEED<',itoa(iPanSpeed),'>'")
    if (iLastPTZ) {
    RecallLastPTZ(iLastPTZ)
    }
}

level_event[vdvObject,ZOOM_SPEED_LVL] {
    iZoomSpeed = level.value
    NAVLog("'VISCA_ZOOM_SPEED_CHANGE<',itoa(iID),'>ZOOM_SPEED<',itoa(iZoomSpeed),'>'")
    if (iLastPTZ) {
    RecallLastPTZ(iLastPTZ)
    }
}

timeline_event[TL_DRIVE] { Drive(); }

timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject,POWER_FB]    = (iActualPower == ACTUAL_POWER_ON)
    [vdvObject,DEVICE_COMMUNICATING] = (iCommunicating)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

