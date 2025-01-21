PROGRAM_NAME='LibVisca'

(***********************************************************)
#include 'NAVFoundation.Core.axi'

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


#IF_NOT_DEFINED __LIB_VISCA__
#DEFINE __LIB_VISCA__ 'LibVisca'

#include 'NAVFoundation.InterModuleApi.axi'


DEFINE_CONSTANT

constant integer DEFAULT_ID = 1

constant char VISCA_COMMAND_SET = $01
constant char VISCA_COMMAND_GET = $09


DEFINE_TYPE

struct _ViscaObject {
    _ModuleObject Api
    integer Id
}


define_function ViscaObjectInit(_ViscaObject object) {
    NAVInterModuleApiInit(object.Api)
    object.Id = DEFAULT_ID
}


define_function char[NAV_MAX_BUFFER] BuildPayload(_ViscaObject object, char type, char value[]) {
    return BuildCustomPayload(object.Id, type, value)
}


define_function char[NAV_MAX_BUFFER] BuildCustomPayload(integer id, char type, char value[]) {
    stack_var char payload[NAV_MAX_BUFFER]

    payload = "id + $80, type, value"

    return payload
}


#END_IF // __LIB_VISCA__
