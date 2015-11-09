/* constants.vala
 *
 * Copyright (C) 2009  Andrea Del Signore
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 * 	Andrea Del Signore <sejerpz@tin.it>
 */

using GLib;
using Vala;

namespace Afrodite
{
	[Flags]
	public enum SymbolAccessibility
	{
		PRIVATE = 1,
		INTERNAL = 1 << 1,
		PROTECTED = 1 << 2,
		PUBLIC = 1 << 3,
		ANY = SymbolAccessibility.PRIVATE | SymbolAccessibility.INTERNAL | SymbolAccessibility.PROTECTED | SymbolAccessibility.PUBLIC
	}

	[Flags]
	public enum MemberBinding {
		INSTANCE = 1,
		CLASS = 1 << 1,
		STATIC = 1 << 2,
		ANY = MemberBinding.INSTANCE | MemberBinding.CLASS | MemberBinding.STATIC
	}
	
	public enum CompareMode
	{
		EXACT,
		START_WITH
	}
	
	public enum CaseSensitiveness
	{
		CASE_SENSITIVE,
		CASE_INSENSITIVE,
		AUTO
	}

	private enum LookupMode
	{
		Symbol,
		Type
	}
}
