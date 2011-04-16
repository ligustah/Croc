/******************************************************************************
This module contains the 'debug' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module minid.debuglib;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils;
import minid.vector;

import minid.interp;

debug import tango.io.Stdout;

struct DebugLib
{
static:
	public void init(MDThread* t)
	{
		makeModule(t, "debug", function uword(MDThread* t)
		{
			newFunction(t, 3, &setHook,        "setHook");        newGlobal(t, "setHook");
			newFunction(t, 1, &getHook,        "getHook");        newGlobal(t, "getHook");
			newFunction(t, 1, &callDepth,      "callDepth");      newGlobal(t, "callDepth");
			newFunction(t, 2, &sourceName,     "sourceName");     newGlobal(t, "sourceName");
			newFunction(t, 2, &sourceLine,     "sourceLine");     newGlobal(t, "sourceLine");
			newFunction(t, 2, &getFunc,        "getFunc");        newGlobal(t, "getFunc");
			newFunction(t, 2, &numLocals,      "numLocals");      newGlobal(t, "numLocals");
			newFunction(t, 3, &localName,      "localName");      newGlobal(t, "localName");
			newFunction(t, 3, &getLocal,       "getLocal");       newGlobal(t, "getLocal");
			newFunction(t, 4, &setLocal,       "setLocal");       newGlobal(t, "setLocal");
			newFunction(t, 2, &numUpvals,      "numUpvals");      newGlobal(t, "numUpvals");
			newFunction(t, 3, &upvalName,      "upvalName");      newGlobal(t, "upvalName");
			newFunction(t, 3, &getUpval,       "getUpval");       newGlobal(t, "getUpval");
			newFunction(t, 4, &setUpval,       "setUpval");       newGlobal(t, "setUpval");
			newFunction(t, 2, &getFuncEnv,     "getFuncEnv");     newGlobal(t, "getFuncEnv");
			newFunction(t, 3, &setFuncEnv,     "setFuncEnv");     newGlobal(t, "setFuncEnv");
			newFunction(t, 2, &currentLine,    "currentLine");    newGlobal(t, "currentLine");
			newFunction(t, 2, &lineInfo,       "lineInfo");       newGlobal(t, "lineInfo");
			newFunction(t, 1, &getMetatable,   "getMetatable");   newGlobal(t, "getMetatable");
			newFunction(t, 2, &setMetatable,   "setMetatable");   newGlobal(t, "setMetatable");
			newFunction(t, 0, &getRegistry,    "getRegistry");    newGlobal(t, "getRegistry");
			newFunction(t, 1, &getExtraBytes,  "getExtraBytes");  newGlobal(t, "getExtraBytes");
			newFunction(t, 2, &setExtraBytes,  "setExtraBytes");  newGlobal(t, "setExtraBytes");
			newFunction(t, 1, &numExtraFields, "numExtraFields"); newGlobal(t, "numExtraFields");
			newFunction(t, 2, &getExtraField,  "getExtraField");  newGlobal(t, "getExtraField");
			newFunction(t, 3, &setExtraField,  "setExtraField");  newGlobal(t, "setExtraField");

			return 0;
		});

		importModuleNoNS(t, "debug");
	}

	ubyte strToMask(char[] str)
	{
		ubyte mask = 0;

		if(str.contains('c')) mask |= MDThread.Hook.Call;
		if(str.contains('r')) mask |= MDThread.Hook.Ret;
		if(str.contains('l')) mask |= MDThread.Hook.Line;

		return mask;
	}

	char[] maskToStr(char[] buf, ubyte mask)
	{
		uword i = 0;

		if(mask & MDThread.Hook.Call)  buf[i++] = 'c';
		if(mask & MDThread.Hook.Ret)   buf[i++] = 'r';
		if(mask & MDThread.Hook.Line)  buf[i++] = 'l';
		if(mask & MDThread.Hook.Delay) buf[i++] = 'd';

		return buf[0 .. i];
	}

	MDThread* getThreadParam(MDThread* t, out word arg)
	{
		if(isValidIndex(t, 1) && isThread(t, 1))
		{
			arg = 1;
			return getThread(t, 1);
		}
		else
		{
			arg = 0;
			return t;
		}
	}

	ActRecord* getAR(MDThread* t, MDThread* thread, mdint depth)
	{
		auto maxDepth = .callDepth(thread);

		if(t is thread)
		{
			// ignore call to whatever this function is
			if(depth < 0 || depth >= maxDepth - 1)
				throwException(t, "invalid call depth {}", depth);

			return getActRec(thread, cast(uword)depth + 1);
		}
		else
		{
			if(depth < 0 || depth >= maxDepth)
				throwException(t, "invalid call depth {}", depth);

			return getActRec(thread, cast(uword)depth);
		}
	}

	MDFunction* getFuncParam(MDThread* t, MDThread* thread, word arg)
	{
		if(isInt(t, arg))
			return getAR(t, thread, getInt(t, arg)).func;
		else if(isFunction(t, arg))
			return getFunction(t, arg);
		else
			paramTypeError(t, arg, "int|function");

		assert(false);
	}

	uword setHook(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		checkAnyParam(t, arg + 1);

		if(!isNull(t, arg + 1) && !isFunction(t, arg + 1))
			paramTypeError(t, arg + 1, "null|function");

		auto maskStr = optStringParam(t, arg + 2, "");
		auto delay = optIntParam(t, arg + 3, 0);

		if(delay < 0 || delay > uword.max)
			throwException(t, "invalid delay value ({})", delay);

		auto mask = strToMask(maskStr);

		if(delay > 0)
			mask |= MDThread.Hook.Delay;

		dup(t, arg + 1);
		transferVals(t, thread, 1);
		setHookFunc(thread, mask, cast(uword)delay);
		return 0;
	}

	uword getHook(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		getHookFunc(thread);
		transferVals(thread, t, 1);
		char[8] buf;
		pushString(t, maskToStr(buf, getHookMask(thread)));
		pushInt(t, getHookDelay(thread));
		return 3;
	}

	uword callDepth(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		if(t is thread)
			pushInt(t, .callDepth(t) - 1); // - 1 to ignore "callDepth" itself
		else
			pushInt(t, .callDepth(thread));

		return 1;
	}

	uword sourceName(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null || func.isNative)
			pushString(t, "");
		else
			pushStringObj(t, func.scriptFunc.location.file);

		return 1;
	}

	uword sourceLine(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null || func.isNative)
			pushInt(t, 0);
		else
			pushInt(t, func.scriptFunc.location.line);

		return 1;
	}

	uword getFunc(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		checkIntParam(t, arg + 1);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			pushNull(t);
		else
			pushFunction(t, func);

		return 1;
	}

	uword numLocals(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));

		if(ar.func is null || ar.func.isNative)
			pushInt(t, 0);
		else
		{
			mdint num = 0;
			auto pc = ar.pc - ar.func.scriptFunc.code.ptr;

			foreach(ref var; ar.func.scriptFunc.locVarDescs)
				if(pc >= var.pcStart && pc < var.pcEnd)
					num++;

			pushInt(t, num);
		}

		return 1;
	}

	uword localName(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));
		auto idx = checkIntParam(t, arg + 2);

		if(idx < 0 || ar.func is null || ar.func.isNative)
			throwException(t, "invalid local index '{}'", idx);

		auto originalIdx = idx;
		auto pc = ar.pc - ar.func.scriptFunc.code.ptr;

		foreach(ref var; ar.func.scriptFunc.locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(idx == 0)
				{
					pushStringObj(t, var.name);
					break;
				}

				idx--;
			}
		}

		if(idx != 0)
			throwException(t, "invalid local index '{}'", originalIdx);

		return 1;
	}

	uword getLocal(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));

		mdint idx = 1;
		MDString* name;

		if(isInt(t, arg + 2))
			idx = getInt(t, arg + 2);
		else if(isString(t, arg + 2))
			name = getStringObj(t, arg + 2);
		else
			paramTypeError(t, arg + 2, "int|string");

		if(idx < 0 || ar.func is null || ar.func.isNative)
			throwException(t, "invalid local index '{}'", idx);

		auto originalIdx = idx;
		auto pc = ar.pc - ar.func.scriptFunc.code.ptr;

		foreach(ref var; ar.func.scriptFunc.locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(name is null)
				{
					if(idx == 0)
					{
						// don't inline; if t is thread, invalid push
						auto v = thread.stack[ar.base + var.reg];
						push(t, v);
						break;
					}

					idx--;
				}
				else if(var.name is name)
				{
					auto v = thread.stack[ar.base + var.reg];
					push(t, v);
					idx = 0;
					break;
				}
			}
		}

		if(idx != 0)
		{
			if(name is null)
				throwException(t, "invalid local index '{}'", originalIdx);
			else
				throwException(t, "invalid local name '{}'", name.toString());
		}

		return 1;
	}

	uword setLocal(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));

		mdint idx = 1;
		MDString* name;

		if(isInt(t, arg + 2))
			idx = getInt(t, arg + 2);
		else if(isString(t, arg + 2))
			name = getStringObj(t, arg + 2);
		else
			paramTypeError(t, arg + 2, "int|string");

		checkAnyParam(t, arg + 3);

		if(idx < 0 || ar.func is null || ar.func.isNative)
			throwException(t, "invalid local index '{}'", idx);

		auto originalIdx = idx;
		auto pc = ar.pc - ar.func.scriptFunc.code.ptr;

		foreach(ref var; ar.func.scriptFunc.locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(name is null)
				{
					if(idx == 0)
					{
						thread.stack[ar.base + var.reg] = *getValue(t, arg + 3);
						break;
					}

					idx--;
				}
				else if(var.name is name)
				{
					thread.stack[ar.base + var.reg] = *getValue(t, arg + 3);
					idx = 0;
					break;
				}
			}
		}

		if(idx != 0)
		{
			if(name is null)
				throwException(t, "invalid local index '{}'", originalIdx);
			else
				throwException(t, "invalid local name '{}'", name.toString());
		}

		return 0;
	}

	uword numUpvals(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			pushInt(t, 0);
		else
			pushInt(t, func.numUpvals);

		return 1;
	}

	uword upvalName(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);
		auto idx = checkIntParam(t, arg + 2);

		if(func is null || idx < 0 || idx >= func.numUpvals)
			throwException(t, "invalid upvalue index '{}'", idx);

		if(func.isNative)
			pushString(t, "");
		else
			pushStringObj(t, func.scriptFunc.upvalNames[cast(uword)idx]);

		return 1;
	}

	uword getUpval(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			throwException(t, "invalid function");

		if(isInt(t, arg + 2))
		{
			auto idx = getInt(t, arg + 2);

			if(idx < 0 || idx >= func.numUpvals)
				throwException(t, "invalid upvalue index '{}'", idx);

			if(func.isNative)
				push(t, func.nativeUpvals()[cast(uword)idx]);
			else
			{
				// don't inline; if t is thread, invalid push
				auto v = *func.scriptUpvals()[cast(uword)idx].value;
				push(t, v);
			}
		}
		else if(isString(t, arg + 2))
		{
			if(func.isNative)
				throwException(t, "cannot get upvalues by name for native functions");

			auto name = getStringObj(t, arg + 2);

			bool found = false;

			foreach(i, n; func.scriptFunc.upvalNames)
			{
				if(n is name)
				{
					found = true;
					auto v = *func.scriptUpvals()[i].value;
					push(t, v);
					break;
				}
			}

			if(!found)
				throwException(t, "invalid upvalue name '{}'", name.toString());
		}
		else
			paramTypeError(t, arg + 2, "int|string");

		return 1;
	}

	uword setUpval(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);
		checkAnyParam(t, arg + 3);

		if(func is null)
			throwException(t, "invalid function");

		if(isInt(t, arg + 2))
		{
			auto idx = getInt(t, arg + 2);

			if(idx < 0 || idx >= func.numUpvals)
				throwException(t, "invalid upvalue index '{}'", idx);

			if(func.isNative)
				func.nativeUpvals()[cast(uword)idx] = *getValue(t, arg + 3);
			else
				*func.scriptUpvals()[cast(uword)idx].value = *getValue(t, arg + 3);
		}
		else if(isString(t, arg + 2))
		{
			if(func.isNative)
				throwException(t, "cannot get upvalues by name for native functions");

			auto name = getStringObj(t, arg + 2);

			bool found = false;

			foreach(i, n; func.scriptFunc.upvalNames)
			{
				if(n is name)
				{
					found = true;

					if(func.isNative)
						func.nativeUpvals()[i] = *getValue(t, arg + 3);
					else
						*func.scriptUpvals()[i].value = *getValue(t, arg + 3);

					break;
				}
			}

			if(!found)
				throwException(t, "invalid upvalue name '{}'", name.toString());
		}
		else
			paramTypeError(t, arg + 2, "int|string");

		return 0;
	}

	uword getFuncEnv(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			throwException(t, "invalid function");

		pushNamespace(t, func.environment);
		return 1;
	}

	uword setFuncEnv(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			throwException(t, "invalid function");

		checkParam(t, arg + 2, MDValue.Type.Namespace);
		pushNamespace(t, func.environment);
		pushFunction(t, func);
		dup(t, arg + 2);
		.setFuncEnv(t, -2);
		pop(t);
		return 1;
	}

	uword currentLine(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto depth = checkIntParam(t, arg + 1);
		auto maxDepth = .callDepth(thread);

		if(t is thread)
		{
			if(depth < 0 || depth >= maxDepth - 1)
				throwException(t, "invalid call depth {}", depth);

			pushInt(t, getDebugLine(t, cast(uword)depth + 1));
		}
		else
		{
			if(depth < 0 || depth >= maxDepth)
				throwException(t, "invalid call depth {}", depth);

			pushInt(t, getDebugLine(t, cast(uword)depth));
		}
		return 1;
	}

	uword lineInfo(MDThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null || func.isNative)
			newArray(t, 0);
		else
		{
			auto info = func.scriptFunc.lineInfo;

			newTable(t, info.length);

			foreach(i, l; info)
			{
				pushBool(t, true);
				idxai(t, -2, l);
			}

			pushNull(t);
			methodCall(t, -2, "keys", 1);
			pushNull(t);
			methodCall(t, -2, "sort", 1);
		}

		return 1;
	}

	uword getMetatable(MDThread* t)
	{
		auto name = checkStringParam(t, 1);

		switch(name)
		{
			case "null":      getTypeMT(t, MDValue.Type.Null);      break;
			case "bool":      getTypeMT(t, MDValue.Type.Bool);      break;
			case "int":       getTypeMT(t, MDValue.Type.Int);       break;
			case "float":     getTypeMT(t, MDValue.Type.Float);     break;
			case "char":      getTypeMT(t, MDValue.Type.Char);      break;
			case "string":    getTypeMT(t, MDValue.Type.String);    break;
			case "table":     getTypeMT(t, MDValue.Type.Table);     break;
			case "array":     getTypeMT(t, MDValue.Type.Array);     break;
			case "function":  getTypeMT(t, MDValue.Type.Function);  break;
			case "class":     getTypeMT(t, MDValue.Type.Class);     break;
			case "instance":  getTypeMT(t, MDValue.Type.Instance);  break;
			case "namespace": getTypeMT(t, MDValue.Type.Namespace); break;
			case "thread":    getTypeMT(t, MDValue.Type.Thread);    break;
			case "nativeobj": getTypeMT(t, MDValue.Type.NativeObj); break;
			case "weakref":   getTypeMT(t, MDValue.Type.WeakRef);   break;

			default:
				throwException(t, "invalid type '{}'", name);
		}

		return 1;
	}
	
	uword setMetatable(MDThread* t)
	{
		auto name = checkStringParam(t, 1);
		
		checkAnyParam(t, 2);

		if(!isNull(t, 2) && !isNamespace(t, 2))
			paramTypeError(t, 2, "null|namespace");

		setStackSize(t, 3);
		
		switch(name)
		{
			case "null":      setTypeMT(t, MDValue.Type.Null);      break;
			case "bool":      setTypeMT(t, MDValue.Type.Bool);      break;
			case "int":       setTypeMT(t, MDValue.Type.Int);       break;
			case "float":     setTypeMT(t, MDValue.Type.Float);     break;
			case "char":      setTypeMT(t, MDValue.Type.Char);      break;
			case "string":    setTypeMT(t, MDValue.Type.String);    break;
			case "table":     setTypeMT(t, MDValue.Type.Table);     break;
			case "array":     setTypeMT(t, MDValue.Type.Array);     break;
			case "function":  setTypeMT(t, MDValue.Type.Function);  break;
			case "class":     setTypeMT(t, MDValue.Type.Class);     break;
			case "instance":  setTypeMT(t, MDValue.Type.Instance);  break;
			case "namespace": setTypeMT(t, MDValue.Type.Namespace); break;
			case "thread":    setTypeMT(t, MDValue.Type.Thread);    break;
			case "nativeobj": setTypeMT(t, MDValue.Type.NativeObj); break;
			case "weakref":   setTypeMT(t, MDValue.Type.WeakRef);   break;

			default:
				throwException(t, "invalid type '{}'", name);
		}

		return 0;
	}
	
	uword getRegistry(MDThread* t)
	{
		.getRegistry(t);
		return 1;
	}

	uword getExtraBytes(MDThread* t)
	{
		checkInstParam(t, 1);
		VectorObj.fromDArray(t, cast(ubyte[]).getExtraBytes(t, 1));
		return 1;
	}

	uword setExtraBytes(MDThread* t)
	{
		checkInstParam(t, 1);
		auto instData = cast(ubyte[]).getExtraBytes(t, 1);
		auto memb = checkInstParam!(VectorObj.Members)(t, 2, "Vector");
		auto vecData = (cast(ubyte*)memb.data)[0 .. memb.length * memb.type.itemSize];

		if(vecData.length != instData.length)
			throwException(t, "Vector size ({}) does not match number of extra bytes ({})", vecData.length, instData.length);

		instData[] = vecData[];
		return 0;
	}

	uword numExtraFields(MDThread* t)
	{
		checkInstParam(t, 1);
		pushInt(t, numExtraVals(t, 1));
		return 1;
	}

	uword getExtraField(MDThread* t)
	{
		checkInstParam(t, 1);
		auto idx = checkIntParam(t, 2);
		auto num = numExtraVals(t, 1);

		if(idx < 0)
			idx += num;

		if(idx < 0 || idx >= num)
			throwException(t, "Invalid field index '{}'", idx);

		getExtraVal(t, 1, cast(uword)idx);
		return 1;
	}

	uword setExtraField(MDThread* t)
	{
		checkInstParam(t, 1);
		auto idx = checkIntParam(t, 2);
		checkAnyParam(t, 3);
		setStackSize(t, 4);
		auto num = numExtraVals(t, 1);

		if(idx < 0)
			idx += num;

		if(idx < 0 || idx >= num)
			throwException(t, "Invalid field index '{}'", idx);

		setExtraVal(t, 1, cast(uword)idx);
		return 0;
	}
}