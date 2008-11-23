/******************************************************************************
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

module minid.oslib;

import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Environment;
import tango.sys.Process;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils;

struct OSLib
{
static:
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			importModule(t, "stream");
			pop(t);

			ProcessObj.init(t);
			newFunction(t, &system, "system"); newGlobal(t, "system");
			newFunction(t, &getEnv, "getEnv"); newGlobal(t, "getEnv");

			return 0;
		}, "os");
		
		fielda(t, -2, "os");
		importModule(t, "os");
		pop(t, 3);
	}

	uword system(MDThread* t, uword numParams)
	{
		if(numParams == 0)
			pushBool(t, .system(null) ? true : false);
		else
		{
			auto cmd = checkStringParam(t, 1);

			if(cmd.length < 128)
			{
				char[128] buf = void;
				buf[0 .. cmd.length] = cmd[];
				buf[cmd.length] = 0;
				pushInt(t, .system(buf.ptr));
			}
			else
			{
				auto arr = t.vm.alloc.allocArray!(char)(cmd.length + 1);
				scope(exit) t.vm.alloc.freeArray(arr);
				arr[0 .. cmd.length] = cmd[];
				arr[cmd.length] = 0;
				pushInt(t, .system(arr.ptr));
			}
		}

		return 1;
	}

	uword getEnv(MDThread* t, uword numParams)
	{
		if(numParams == 0)
		{
			newTable(t);

			foreach(k, v; Environment.get())
			{
				pushString(t, k);
				pushString(t, v);
				idxa(t, -3);
			}
		}
		else
		{
			auto val = Environment.get(checkStringParam(t, 1), optStringParam(t, 2, null));

			if(val is null)
				pushNull(t);
			else
				pushString(t, val);
		}

		return 1;
	}

	struct ProcessObj
	{
	static:
		enum Fields
		{
			process,
			stdin,
			stdout,
			stderr
		}

		public static void init(MDThread* t)
		{
			CreateClass(t, "Process", (CreateClass* c)
			{
				c.method("constructor", &constructor);
				c.method("isRunning",   &isRunning);
				c.method("workDir",     &workDir);
				c.method("stdin",       &stdin);
				c.method("stdout",      &stdout);
				c.method("stderr",      &stderr);
				c.method("execute",     &execute);
				c.method("wait",        &wait);
				c.method("kill",        &kill);
			});
			
			newFunction(t, &allocator, "Process.allocator");
			setAllocator(t, -2);

			newGlobal(t, "Process");
		}

		Process getProcess(MDThread* t)
		{
			checkInstParam(t, 0, "Process");
			getExtraVal(t, 0, Fields.process);
			auto ret = cast(Process)getNativeObj(t, -1);
			assert(ret !is null);
			pop(t);
			return ret;
		}
		
		uword allocator(MDThread* t, uword numParams)
		{
			newInstance(t, 0, Fields.max + 1);
			
			dup(t);
			pushNull(t);
			rotateAll(t, 3);
			methodCall(t, 2, "constructor", 0);
			return 1;
		}

		public uword constructor(MDThread* t, uword numParams)
		{
			checkInstParam(t, 0, "Process");
			pushNativeObj(t, new Process());
			setExtraVal(t, 0, Fields.process);
			return 0;
		}

		public uword isRunning(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);
			pushBool(t, safeCode(t, p.isRunning()));
			return 1;
		}

		public uword workDir(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			if(numParams == 0)
			{
				pushString(t, safeCode(t, p.workDir));
				return 1;
			}

			safeCode(t, p.workDir = checkStringParam(t, 1));
			return 0;
		}

		public uword execute(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			char[][char[]] env = null;

			if(numParams > 1)
			{
				checkParam(t, 2, MDValue.Type.Table);
				dup(t, 2);

				foreach(word k, word v; foreachLoop(t, 1))
				{
					if(!isString(t, k) || !isString(t, v))
						throwException(t, "env parameter must be a table mapping from strings to strings");

					env[getString(t, k)] = getString(t, v);
				}
			}
			
			if(isString(t, 1))
				safeCode(t, p.execute(getString(t, 1), env));
			else
			{
				checkParam(t, 1, MDValue.Type.Array);
				auto num = len(t, 1);
				auto cmd = new char[][cast(uword)num];

				for(uword i = 0; i < num; i++)
				{
					idxi(t, 1, i);
					
					if(!isString(t, -1))
						throwException(t, "cmd parameter must be an array of strings");

					cmd[i] = getString(t, -1);
					pop(t);
				}

				safeCode(t, p.execute(cmd, env));
			}

			pushNull(t);
			dup(t);
			dup(t);
			setExtraVal(t, 0, Fields.stdin);
			setExtraVal(t, 0, Fields.stdout);
			setExtraVal(t, 0, Fields.stderr);

			return 0;
		}
		
		public uword stdin(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			getExtraVal(t, 0, Fields.stdin);
			
			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("stream.OutputStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stdin.output);
				rawCall(t, -3, 1);
				dup(t);
				setExtraVal(t, 0, Fields.stdin);
			}

			return 1;
		}
		
		public uword stdout(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			getExtraVal(t, 0, Fields.stdout);
			
			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("stream.InputStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stdout.input);
				rawCall(t, -3, 1);
				dup(t);
				setExtraVal(t, 0, Fields.stdout);
			}

			return 1;
		}
		
		public uword stderr(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			getExtraVal(t, 0, Fields.stderr);
			
			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("stream.InputStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stderr.input);
				rawCall(t, -3, 1);
				dup(t);
				setExtraVal(t, 0, Fields.stderr);
			}

			return 1;
		}
		
		public uword wait(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);
			
			getExtraVal(t, 0, Fields.stdin);
			
			if(!isNull(t, -1))
			{
				pushNull(t);
				methodCall(t, -2, "flush", 0);
			}
			else
				pop(t);

			auto res = safeCode(t, p.wait());

			switch(res.reason)
			{
				case Process.Result.Exit:     pushString(t, "exit"); break;
				case Process.Result.Signal:   pushString(t, "signal"); break;
				case Process.Result.Stop:     pushString(t, "stop"); break;
				case Process.Result.Continue: pushString(t, "continue"); break;
				case Process.Result.Error:    pushString(t, "error"); break;
				default: assert(false);
			}

			pushInt(t, res.status);
			return 2;
		}

		public uword kill(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);
			safeCode(t, p.kill());
			return 0;
		}
	}
}