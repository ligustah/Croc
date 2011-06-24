/******************************************************************************
This module contains the 'char' standard library.

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

module croc.stdlib_char;

import tango.stdc.ctype;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import croc.api_interpreter;
import croc.ex;
import croc.types;

struct CharLib
{
static:
	public void init(CrocThread* t)
	{
		newNamespace(t, "char");
			newFunction(t, 0, &toLower,    "char.toLower");    fielda(t, -2, "toLower");
			newFunction(t, 0, &toUpper,    "char.toUpper");    fielda(t, -2, "toUpper");
			newFunction(t, 0, &isAlpha,    "char.isAlpha");    fielda(t, -2, "isAlpha");
			newFunction(t, 0, &isAlNum,    "char.isAlNum");    fielda(t, -2, "isAlNum");
			newFunction(t, 0, &isLower,    "char.isLower");    fielda(t, -2, "isLower");
			newFunction(t, 0, &isUpper,    "char.isUpper");    fielda(t, -2, "isUpper");
			newFunction(t, 0, &isDigit,    "char.isDigit");    fielda(t, -2, "isDigit");
			newFunction(t, 0, &isCtrl,     "char.isCtrl");     fielda(t, -2, "isCtrl");
			newFunction(t, 0, &isPunct,    "char.isPunct");    fielda(t, -2, "isPunct");
			newFunction(t, 0, &isSpace,    "char.isSpace");    fielda(t, -2, "isSpace");
			newFunction(t, 0, &isHexDigit, "char.isHexDigit"); fielda(t, -2, "isHexDigit");
			newFunction(t, 0, &isAscii,    "char.isAscii");    fielda(t, -2, "isAscii");
			newFunction(t, 0, &isValid,    "char.isValid");    fielda(t, -2, "isValid");
		setTypeMT(t, CrocValue.Type.Char);
	}

	uword toLower(CrocThread* t)
	{
		dchar[4] outbuf = void;
		dchar c = checkCharParam(t, 0);
		pushChar(t, safeCode(t, Uni.toLower((&c)[0 .. 1], outbuf)[0]));
		return 1;
	}

	uword toUpper(CrocThread* t)
	{
		dchar[4] outbuf = void;
		dchar c = checkCharParam(t, 0);
		pushChar(t, safeCode(t, Uni.toUpper((&c)[0 .. 1], outbuf)[0]));
		return 1;
	}

	uword isAlpha(CrocThread* t)
	{
		pushBool(t, Uni.isLetter(checkCharParam(t, 0)));
		return 1;
	}

	uword isAlNum(CrocThread* t)
	{
		pushBool(t, Uni.isLetterOrDigit(checkCharParam(t, 0)));
		return 1;
	}

	uword isLower(CrocThread* t)
	{
		pushBool(t, Uni.isLower(checkCharParam(t, 0)));
		return 1;
	}

	uword isUpper(CrocThread* t)
	{
		pushBool(t, Uni.isUpper(checkCharParam(t, 0)));
		return 1;
	}

	uword isDigit(CrocThread* t)
	{
		pushBool(t, Uni.isDigit(checkCharParam(t, 0)));
		return 1;
	}

	uword isCtrl(CrocThread* t)
	{
		pushBool(t, cast(bool)iscntrl(checkCharParam(t, 0)));
		return 1;
	}

	uword isPunct(CrocThread* t)
	{
		pushBool(t, cast(bool)ispunct(checkCharParam(t, 0)));
		return 1;
	}

	uword isSpace(CrocThread* t)
	{
		pushBool(t, cast(bool)isspace(checkCharParam(t, 0)));
		return 1;
	}

	uword isHexDigit(CrocThread* t)
	{
		pushBool(t, cast(bool)isxdigit(checkCharParam(t, 0)));
		return 1;
	}

	uword isAscii(CrocThread* t)
	{
		pushBool(t, checkCharParam(t, 0) <= 0x7f);
		return 1;
	}

	uword isValid(CrocThread* t)
	{
		pushBool(t, Utf.isValid(checkCharParam(t, 0)));
		return 1;
	}
}