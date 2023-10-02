MODULE_NAME='mViscaCameraComm'      (
                                        dev vdvObject,
                                        dev vdvCommObjects[],
                                        dev dvPort
                                    )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'

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
constant long TL_IP_CHECK = 1
constant long TL_QUEUE_FAILED_RESPONSE    = 2
constant long TL_HEARTBEAT    = 3

constant integer MAX_QUEUE_COMMANDS = 50
constant integer MAX_QUEUE_STATUS = 100
constant integer MAX_OBJECTS    = 8

constant integer TELNET_WILL    = $FB
constant integer TELNET_DO    = $FD
constant integer TELNET_DONT    = $FE
constant integer TELNET_WONT    = $FC


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE
struct _Object {
    integer iInitialized
    integer iRegistered
}

struct _Queue {
    integer iBusy
    integer iHasItems
    integer iCommandHead
    integer iCommandTail
    integer iStatusHead
    integer iStatusTail
    integer iStrikeCount
    integer iResendLast
    char cLastMess[NAV_MAX_BUFFER]
}

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE
volatile long ltHeartbeat[] = { 30000 }
volatile long ltIPCheck[] = { 3000 }
volatile long ltQueueFailedResponse[]    = { 2500 }

volatile _Object uObject[MAX_OBJECTS]

volatile _Queue uQueue
volatile char cCommandQueue[MAX_QUEUE_COMMANDS][NAV_MAX_BUFFER]
volatile char cStatusQueue[MAX_QUEUE_STATUS][NAV_MAX_BUFFER]

volatile char cRxBuffer[NAV_MAX_BUFFER]
volatile integer iSemaphore

volatile char cIPAddress[15]
volatile integer iIPConnected = false
volatile integer iIPAuthenticated

volatile integer iInitializing
volatile integer iInitializingObjectID

volatile integer iInitialized
volatile integer iCommunicating

volatile integer iReadyToInitialize

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
define_function SendStringRaw(char cString[]) {
    NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, cString))
    send_string dvPort,"cString"
}

define_function SendString(char cString[]) {
    NAVLog("'Formatting String'")
    SendStringRaw("cString,$FF")
}

/*
define_function BuildCommand(char cHeader[], char cCmd[]) {
    if (length_array(cCmd)) {
    SendCommand("cHeader,'-<',itoa(iID),'|',cCmd,'>'")
    }else {
    SendCommand("cHeader,'-<',itoa(iID),'>'")
    }
}
*/
/*
define_function char[NAV_MAX_BUFFER] BuildString(char cInst[], char cCmd[], char cAtt[], char cIndex1[], char cIndex2[], char cVal[]) {
    stack_var char cTemp[NAV_MAX_BUFFER]
    if (length_array(cInst)) { cTemp = "cTemp,cInst,' '" }
    if (length_array(cCmd)) { cTemp = "cTemp,cCmd,' '" }
    if (length_array(cAtt)) { cTemp = "cTemp,cAtt,' '" }
    if (length_array(cIndex1)) { cTemp = "cTemp,cIndex1,' '" }
    if (length_array(cIndex2)) { cTemp = "cTemp,cIndex2,' '" }
    if (length_array(cVal)) { cTemp = "cTemp,cVal" }
    if (right_string(cTemp, 1) == ' ') { cTemp = NAVStripCharsFromRight(cTemp, 1) }
    return cTemp
}
*/
define_function AddToQueue(char cString[], integer iPriority) {
    stack_var integer iQueueWasEmpty
    NAVLog("'Adding to Queue'")
    iQueueWasEmpty = (!uQueue.iHasItems && !uQueue.iBusy)
    switch (iPriority) {
    case true: {    //Commands have priority over status requests
        select {
        active (uQueue.iCommandHead == max_length_array(cCommandQueue)): {
            if (uQueue.iCommandTail <> 1) {
            uQueue.iCommandHead = 1
            cCommandQueue[uQueue.iCommandHead] = cString
            uQueue.iHasItems = true
            }
        }
        active (uQueue.iCommandTail <> (uQueue.iCommandHead + 1)): {
            uQueue.iCommandHead++
            cCommandQueue[uQueue.iCommandHead] = cString
            uQueue.iHasItems = true
        }
        }
    }
    case false: {
        select {
        active (uQueue.iStatusHead == max_length_array(cStatusQueue)): {
            if (uQueue.iStatusTail <> 1) {
            uQueue.iStatusHead = 1
            cStatusQueue[uQueue.iStatusHead] = cString
            uQueue.iHasItems = true
            }
        }
        active (uQueue.iStatusTail <> (uQueue.iStatusHead + 1)): {
            uQueue.iStatusHead++
            cStatusQueue[uQueue.iStatusHead] = cString
            uQueue.iHasItems = true
        }
        }
    }
    }

    if (iQueueWasEmpty) { SendNextQueueItem(); NAVLog("'Queue was empty. Sending Next'") }
}

define_function char[NAV_MAX_BUFFER] RemoveFromQueue() {
    NAVLog("'Removing from Queue'")
    if (uQueue.iHasItems && !uQueue.iBusy) {
    uQueue.iBusy = true
    select {
        active (uQueue.iCommandHead <> uQueue.iCommandTail): {
        if (uQueue.iCommandTail == max_length_array(cCommandQueue)) {
            uQueue.iCommandTail = 1
        }else {
            uQueue.iCommandTail++
        }

        uQueue.cLastMess = cCommandQueue[uQueue.iCommandTail]
        }
        active (uQueue.iStatusHead <> uQueue.iStatusTail): {
        if (uQueue.iStatusTail == max_length_array(cStatusQueue)) {
            uQueue.iStatusTail = 1
        }else {
            uQueue.iStatusTail++
        }

        uQueue.cLastMess = cStatusQueue[uQueue.iStatusTail]
        }
    }

    if ((uQueue.iCommandHead == uQueue.iCommandTail) && (uQueue.iStatusHead == uQueue.iStatusTail)) {
        uQueue.iHasItems = false
    }

    NAVLog("'Last Mess: ',uQueue.cLastMess")
    return GetMess(uQueue.cLastMess)
    }

    return ''
}

define_function integer GetMessID(char cParam[]) {
    return atoi(NAVGetStringBetween(cParam,'<','|'))
}

define_function integer GetSubscriptionMessID(char cParam[]) {
    return atoi(NAVGetStringBetween(cParam,'[','*'))
}

define_function char[NAV_MAX_BUFFER] GetMess(char cParam[]) {
    NAVLog("'Got Mess: ',NAVGetStringBetween(cParam,'|','>')")
    return NAVGetStringBetween(cParam,'|','>')
}

define_function InitializeObjects() {
    stack_var integer x
    if (!iInitializing) {
    for (x = 1; x <= length_array(vdvCommObjects); x++) {
        if (uObject[x].iRegistered && !uObject[x].iInitialized) {
        iInitializing = true
        send_string vdvCommObjects[x],"'INIT<',itoa(x),'>'"
        NAVLog("'VISCA_INIT<',itoa(x),'>'")
        iInitializingObjectID = x
        break
        }

        if (x == length_array(vdvCommObjects) && !iInitializing) {
        iInitializingObjectID = x
        iInitialized = true
        }
    }
    }
}

define_function GoodResponse() {
    NAVLog("'Good Response'")
    uQueue.iBusy = false
    NAVTimelineStop(TL_QUEUE_FAILED_RESPONSE)

    uQueue.iStrikeCount = 0
    uQueue.iResendLast = false
    SendNextQueueItem()
}

define_function SendNextQueueItem() {
    stack_var char cTemp[NAV_MAX_BUFFER]
   NAVLog("'Sending Next'")
    if (uQueue.iResendLast) {
    NAVLog("'Resending Last'")
    uQueue.iResendLast = false
    cTemp = GetMess(uQueue.cLastMess)
    }else {
    NAVLog("'Requesting from queue'")
    cTemp= RemoveFromQueue()
    }

    if (length_array(cTemp)) {
    NAVLog("'Requesting to send'")
    SendString(cTemp)
    //if (NAVContains(cTemp,'*')) {
        //wait 10 GoodResponse()    //Move straight on without waiting for response if a global command was sent
    //}else {
        timeline_create(TL_QUEUE_FAILED_RESPONSE,ltQueueFailedResponse,length_array(ltQueueFailedResponse),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
    //}
    }
}

define_event timeline_event[TL_QUEUE_FAILED_RESPONSE] {
    if (uQueue.iBusy) {
    if (uQueue.iStrikeCount < 3) {
        uQueue.iStrikeCount++
        uQueue.iResendLast = true
        SendNextQueueItem()
    }else {
        iCommunicating = false
        Reset()
    }
    }
}

define_function Reset() {
    ReInitializeObjects()
    InitializeQueue()
}

define_function ReInitializeObjects() {
    stack_var integer x
    iInitializing = false
    iInitialized = false
    iInitializingObjectID = 1
    for (x = 1; x <= length_array(uObject); x++) {
    uObject[x].iInitialized = false
    }
}

define_function InitializeQueue() {
    uQueue.iBusy = false
    uQueue.iHasItems = false
    uQueue.iCommandHead = 1
    uQueue.iCommandTail = 1
    uQueue.iStatusHead = 1
    uQueue.iStatusTail = 1
    uQueue.iStrikeCount = 0
    uQueue.iResendLast = false
    uQueue.cLastMess = "''"
}

define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]
    iSemaphore = true
    while (length_array(cRxBuffer) && NAVContains(cRxBuffer,"$FF")) {
    cTemp = remove_string(cRxBuffer,"$FF",1)
    if (length_array(cTemp)) {
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM, dvPort, cTemp))
        cTemp = NAVStripCharsFromRight(cTemp, 1)    //Removes FF
        select {
        active (NAVContains(uQueue.cLastMess,'HEARTBEAT')): {
            if (!iCommunicating) {
            iCommunicating = true
            }

            if (iCommunicating && !iInitialized && iReadyToInitialize) {
            InitializeObjects()
            }

            //GoodResponse()
        }
        active (1): {
            stack_var integer iResponseMessID
            iResponseMessID = GetMessID(uQueue.cLastMess)
            if (iResponseMessID && (iResponseMessID <= length_array(vdvCommObjects))) {
            send_string vdvCommObjects[iResponseMessID],"'RESPONSE_MSG<',GetMess(uQueue.cLastMess),'|',cTemp,'>'"
            }
        }
        }

        GoodResponse()
    }
    }

    iSemaphore = false
}

define_function MaintainIPConnection() {
    if (!iIPConnected) {
    NAVClientSocketOpen(dvPort.port,cIPAddress,NAV_TELNET_PORT,IP_TCP)
    }
}

(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort,cRxBuffer
    Reset()
}
(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT
data_event[dvPort] {
    online: {
    if (data.device.number <> 0) {
        send_command data.device,"'SET BAUD 9600,N,8,1 485 DISABLE'"
        send_command data.device,"'B9MOFF'"
        send_command data.device,"'CHARD-0'"
        send_command data.device,"'CHARDM-0'"
        send_command data.device,"'HSOFF'"
    }

    if (data.device.number <> 0) {
        timeline_create(TL_HEARTBEAT,ltHeartbeat,length_array(ltHeartbeat),TIMELINE_ABSOLUTE,TIMELINE_REPEAT)
    }

    if (data.device.number == 0) { iIPConnected = true }
    }
    string: {
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, data.device, data.text))
        select {
        active (1): {
            if (!iSemaphore) { Process() }
        }
        }
    }
    offline: {
    if (data.device.number == 0) {
        NAVClientSocketClose(dvPort.port)
        iIPConnected = false
        iIPAuthenticated = false
        iCommunicating = false
        NAVTimelineStop(TL_HEARTBEAT)
    }
    }
    onerror: {
    if (data.device.number == 0) {
        //iIPConnected = false
        //iIPAuthenticated = false
        //iCommunicating = false
        //if (timeline_active(TL_HEARTBEAT)) {
    //    NAVTimelineStop(TL_HEARTBEAT)
       // }
    }
    }
}

data_event[vdvObject] {
    command: {
        stack_var char cCmdHeader[NAV_MAX_CHARS]
    stack_var char cCmdParam[2][NAV_MAX_CHARS]
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))
        cCmdHeader = DuetParseCmdHeader(data.text)
        cCmdParam[1] = DuetParseCmdParam(data.text)
        cCmdParam[2] = DuetParseCmdParam(data.text)
        switch (cCmdHeader) {
        case 'PROPERTY': {
            switch (cCmdParam[1]) {
            case 'IP_ADDRESS': {
                cIPAddress = cCmdParam[2]
                timeline_create(TL_IP_CHECK,ltIPCheck,length_array(ltIPCheck),timeline_absolute,timeline_repeat)
            }
            case 'USER_NAME': {
                //cUserName = cCmdParam[2]
            }
            case 'PASSWORD': {
                //cPassword = cCmdParam[2]
            }
            }
        }

        /*
        case 'INIT': {
            stack_var integer x
            for (x = 1; x <= length_array(vdvCommObjects); x++) {
            send_string vdvCommObjects[x],"'REGISTER<',itoa(x),'>'"
            NAVLog("'VISCA_REGISTER_SENT<',itoa(x),'>'")
            }

            //iReadyToInitialize = true
        }
        */
        }
    }
}

data_event[vdvCommObjects] {
    online: {
    send_string data.device,"'REGISTER<',itoa(get_last(vdvCommObjects)),'>'"
    }
    command: {
        stack_var char cCmdHeader[NAV_MAX_CHARS]
        stack_var integer iResponseObjectMessID
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))
        cCmdHeader = DuetParseCmdHeader(data.text)
        switch (cCmdHeader) {
        case 'COMMAND_MSG': { AddToQueue("cCmdHeader,data.text",true); }// NAVLog("'COMMAND_MSG_RECEIVED: ',data.text") }
        case 'POLL_MSG': { AddToQueue("cCmdHeader,data.text",false) }
        case 'RESPONSE_OK': {
            if (NAVGetStringBetween(data.text,'<','>') == NAVGetStringBetween(uQueue.cLastMess,'<','>')) {
            GoodResponse()
            }
        }
        case 'INIT_DONE': {
            iInitializing = false
            iResponseObjectMessID = atoi(NAVGetStringBetween(data.text,'<','>'))
            uObject[get_last(vdvCommObjects)].iInitialized = true
            InitializeObjects()
            if (iResponseObjectMessID == length_array(vdvCommObjects)) {
            stack_var integer x
            for (x = 1; x <= length_array(vdvCommObjects); x++) {
                send_string vdvCommObjects[x],"'START_POLLING<',itoa(x),'>'"
            }

            //Init is Done!
            send_string vdvObject,"'INIT_DONE'"
            }
        }
        case 'REGISTER': {
            iResponseObjectMessID = atoi(NAVGetStringBetween(data.text,'<','>'))
            uObject[get_last(vdvCommObjects)].iRegistered = true
            if (get_last(vdvCommObjects) == length_array(vdvCommObjects)) {
            iReadyToInitialize = true
            }
        }
        }
    }
}

timeline_event[TL_HEARTBEAT] {
    NAVLog("'Heartbeat TimeLine Running'")
    if (!uQueue.iHasItems && !uQueue.iBusy) {
    AddToQueue("'POLL_MSG<HEARTBEAT|',$81,$09,$04,$00,'>'",false)
    }
}

timeline_event[TL_IP_CHECK] { MaintainIPConnection() }

timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject,NAV_IP_CONNECTED]    = (iIPConnected && iIPAuthenticated)
    [vdvObject,DEVICE_COMMUNICATING] = (iCommunicating)
    [vdvObject,DATA_INITIALIZED] = (iInitialized)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

