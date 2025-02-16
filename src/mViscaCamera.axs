MODULE_NAME='mViscaCamera'      (
                                    dev vdvObject,
                                    dev vdvCommObject
                                )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_STRING_GATHER_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.ArrayUtils.axi'
#include 'NAVFoundation.InterModuleApi.axi'
#include 'LibVisca.axi'

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

constant long TL_DRIVE_INTERVAL[] = { 500 }

constant integer REQUIRED_POWER_ON      = 1
constant integer REQUIRED_POWER_OFF     = 2

constant integer ACTUAL_POWER_ON        = 1
constant integer ACTUAL_POWER_OFF       = 2

constant integer GET_POWER  = 1
constant integer GET_PAN    = 2
constant integer GET_ZOOM   = 3


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile integer loop

volatile integer commandLockOut

volatile integer requiredPower
volatile integer actualPower

volatile integer pollSequence = GET_POWER

volatile integer tiltSpeed      = 5
volatile integer panSpeed       = 5
volatile integer zoomSpeed      = 2

volatile integer lastPTZ

volatile _ViscaObject object

volatile integer registerReady
volatile integer registerRequested

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

define_function Register(_ViscaObject object) {
    stack_var char message[NAV_MAX_BUFFER]

    if (!registerRequested || !registerReady || !object.Api.Id) {
        return
    }

    message = NAVInterModuleApiBuildObjectMessage(OBJECT_REGISTRATION_MESSAGE_HEADER,
                                    object.Api.Id,
                                    '')

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mViscaCamera => ID-', itoa(object.Api.Id), ' Data-', message")

    NAVInterModuleApiSendObjectMessage(vdvCommObject, message)

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mViscaCamera => Object Registering: ID-', itoa(object.Api.Id)")

    object.Api.IsRegistered = true
}


#IF_DEFINED USING_NAV_STRING_GATHER_CALLBACK
define_function NAVStringGatherCallback(_NAVStringGatherResult args) {
    stack_var integer id

    id = NAVInterModuleApiGetObjectId(args.Data)

    select {
        active (NAVStartsWith(args.Data, OBJECT_REGISTRATION_MESSAGE_HEADER)): {
            // object.Api.Id = NAVInterModuleApiGetObjectId(args.Data)
            object.Api.Id = id

            registerRequested = true
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                        "'mViscaCamera => Object Registration Requested: ID-', itoa(object.Api.Id)")

            Register(object)
        }
        active (NAVStartsWith(args.Data, OBJECT_INIT_MESSAGE_HEADER)): {
            object.Api.IsInitialized = false
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                        "'mViscaCamera => Object Initialization Requested: ID-', itoa(object.Api.Id)")

            GetInitialized(object)
            pollSequence = GET_POWER
        }
        active (NAVStartsWith(args.Data, OBJECT_START_POLLING_MESSAGE_HEADER)): {
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                        "'mViscaCamera => Object Polling Requested: ID-', itoa(object.Api.Id)")

            StartPolling(object)
        }
        active (NAVStartsWith(args.Data, OBJECT_RESPONSE_MESSAGE_HEADER)): {
            stack_var char response[NAV_MAX_BUFFER]

            response = NAVInterModuleApiGetObjectFullMessage(args.Data)

            {
                stack_var char responseRequestMess[NAV_MAX_BUFFER]
                stack_var char responseMess[NAV_MAX_BUFFER]

                CommunicationTimeOut(30)

                responseRequestMess = NAVGetStringBetween(response, '<', '|')
                responseMess = NAVGetStringBetween(response, '|', '>')

                select {
                    active (NAVContains(responseMess, "object.Id + $8F, $50")): {
                        remove_string(responseMess, "object.Id + $8F, $50", 1)

                        switch (pollSequence) {
                            case GET_POWER: {
                                switch (responseMess[1]) {
                                    case $02: { actualPower = ACTUAL_POWER_ON }
                                    case $03: { actualPower = ACTUAL_POWER_OFF }
                                }

                                if (!module.Device.IsInitialized) {
                                    module.Device.IsInitialized = true
                                    NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                                        NAVInterModuleApiBuildObjectMessage(OBJECT_INIT_DONE_MESSAGE_HEADER,
                                                                            object.Api.Id,
                                                                            ''))
                                }
                            }
                            case GET_PAN: {
                                pollSequence = GET_POWER
                            }
                            case GET_ZOOM: {
                                pollSequence = GET_POWER
                            }
                        }
                    }
                }
            }
        }
    }
}
#END_IF


define_function StartPolling(_ViscaObject object) {
    NAVTimelineStart(TL_DRIVE, TL_DRIVE_INTERVAL, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
}


define_function GetInitialized(_ViscaObject object) {
    SendQuery(GET_POWER)
}


define_function SendQuery(integer query) {
    switch (query) {
        case GET_POWER: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                NAVInterModuleApiBuildObjectMessage(OBJECT_QUERY_MESSAGE_HEADER,
                                                    object.Api.Id,
                                                    BuildPayload(object, VISCA_COMMAND_GET, "$04, $00")))
        }
        case GET_PAN: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                NAVInterModuleApiBuildObjectMessage(OBJECT_QUERY_MESSAGE_HEADER,
                                                    object.Api.Id,
                                                    BuildPayload(object, VISCA_COMMAND_GET, "$06, $12")))
        }
        case GET_ZOOM: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                NAVInterModuleApiBuildObjectMessage(OBJECT_QUERY_MESSAGE_HEADER,
                                                    object.Api.Id,
                                                    BuildPayload(object, VISCA_COMMAND_GET, "$04, $47")))
        }
    }
}


define_function CommunicationTimeOut(integer timeOut) {
    cancel_wait 'CommsTimeOut'

    module.Device.IsCommunicating = true

    wait (timeOut * 10) 'CommsTimeOut' {
        module.Device.IsCommunicating = false
    }
}


define_function SetPower(integer state) {
    switch (state) {
        case REQUIRED_POWER_ON: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $00, $02")))
        }
        case REQUIRED_POWER_OFF: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $00, $03")))
        }
    }
}


define_function Drive() {
    loop++

    switch (loop) {
        case 1:
        case 11:
        case 21:
        case 31: {
            SendQuery(pollSequence)
            return
        }
        case 41: {
            loop = 0
            return
        }
        default: {
            if (commandLockOut) { return }

            if (requiredPower && (requiredPower == actualPower)) { requiredPower = 0; return }

            if (requiredPower && (requiredPower != actualPower) && module.Device.IsCommunicating) {
                SetPower(requiredPower)

                commandLockOut = true
                wait 150 commandLockOut = false

                pollSequence = GET_POWER

                return
            }
        }
    }
}


define_function RecallLastPTZ(integer last) {
    switch (last) {
        case 1: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $03, $01")))

        }
        case 2: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $03, $02")))
        }
        case 3: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $01, $03")))
        }
        case 4: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $02, $03")))
        }
        case 5: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $07, $20 + zoomSpeed")))
        }
        case 6: {
            NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $07, $30 + zoomSpeed")))
        }
    }
}


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    switch (upper_string(event.Name)) {
        case 'UNIT_ID':
        case 'ID': {
            object.Id = atoi(NAVTrimString(event.Args[1]))
        }
    }
}
#END_IF


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer vdvCommObject, module.RxBuffer.Data

    set_virtual_channel_count(vdvObject, 1024)
    set_virtual_level_count(vdvObject, 30)
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[vdvCommObject] {
    string: {
        NAVStringGather(module.RxBuffer, '>')
    }
}


data_event[vdvObject] {
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            case OBJECT_REGISTRATION_MESSAGE_HEADER: {
                registerReady = true

                Register(object)
            }
            case OBJECT_INIT_MESSAGE_HEADER: {
                GetInitialized(object)
            }
            case 'POWER': {
                switch (message.Parameter[1]) {
                    case 'ON': {
                        requiredPower = REQUIRED_POWER_ON
                        Drive()
                    }
                    case 'OFF': {
                        requiredPower = REQUIRED_POWER_OFF
                        Drive()
                    }
                }
            }
            case 'PRESET': {
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object,
                                                                    VISCA_COMMAND_SET,
                                                                    "$04, $3F, $02, atoi(message.Parameter[1]), $FF")))
            }
            case 'PRESETSAVE': {
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object,
                                                                    VISCA_COMMAND_SET,
                                                                    "$04, $3F, $01, atoi(message.Parameter[1]), $FF")))
            }
        }
    }
}


channel_event[vdvObject, 0] {
    on: {
        switch (channel.channel) {
            case PWR_ON: {
                requiredPower = REQUIRED_POWER_ON
                Drive()
            }
            case PWR_OFF: {
                requiredPower = REQUIRED_POWER_OFF
                Drive()
            }
            case TILT_UP: {
                lastPTZ = 1
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $03, $01")))
            }
            case TILT_DN: {
                lastPTZ = 2
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $03, $02")))
            }
            case PAN_LT: {
                lastPTZ = 3
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $01, $03")))
            }
            case PAN_RT: {
                lastPTZ = 4
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $02, $03")))
            }
            case ZOOM_IN: {
                lastPTZ = 5
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $07, $20 + zoomSpeed")))
            }
            case ZOOM_OUT: {
                lastPTZ = 6
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $07, $30 + zoomSpeed")))
            }
            case NAV_PRESET_1:
            case NAV_PRESET_2:
            case NAV_PRESET_3:
            case NAV_PRESET_4:
            case NAV_PRESET_5:
            case NAV_PRESET_6:
            case NAV_PRESET_7:
            case NAV_PRESET_8: {
                stack_var integer preset

                preset = NAVFindInArrayInteger(NAV_PRESET, channel.channel)

                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object,
                                                                    VISCA_COMMAND_SET,
                                                                    "$04, $3F, $02, preset, $FF")))
            }
        }
    }
    off: {
        switch (channel.channel) {
            case TILT_UP:
            case TILT_DN:
            case PAN_LT:
            case PAN_RT: {
                lastPTZ = 0
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$06, $01, tiltSpeed, panSpeed, $03, $03")))
            }
            case ZOOM_IN:
            case ZOOM_OUT: {
                lastPTZ = 0
                NAVInterModuleApiSendObjectMessage(vdvCommObject,
                                    NAVInterModuleApiBuildObjectMessage(OBJECT_COMMAND_MESSAGE_HEADER,
                                                        object.Api.Id,
                                                        BuildPayload(object, VISCA_COMMAND_SET, "$04, $07, $00")))
            }
        }
    }
}


level_event[vdvObject, TILT_SPEED_LVL] {
    tiltSpeed = level.value

    // NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
    //             "'VISCA_TILT_SPEED_CHANGE<', itoa(iD), '>TILT_SPEED<', itoa(tiltSpeed), '>'")

    if (lastPTZ) {
        RecallLastPTZ(lastPTZ)
    }
}


level_event[vdvObject, PAN_SPEED_LVL] {
    panSpeed = level.value

    // NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
    //             "'VISCA_PAN_SPEED_CHANGE<', itoa(iD), '>PAN_SPEED<', itoa(panSpeed), '>'")

    if (lastPTZ) {
        RecallLastPTZ(lastPTZ)
    }
}


level_event[vdvObject, ZOOM_SPEED_LVL] {
    zoomSpeed = level.value

    // NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
    //             "'VISCA_ZOOM_SPEED_CHANGE<', itoa(iD), '>ZOOM_SPEED<', itoa(zoomSpeed), '>'")

    if (lastPTZ) {
        RecallLastPTZ(lastPTZ)
    }
}


timeline_event[TL_DRIVE] { Drive(); }


timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject, POWER_FB]    = (actualPower == ACTUAL_POWER_ON)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
