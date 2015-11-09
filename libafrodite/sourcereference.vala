/* sourcereference.vala
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

namespace Afrodite
{
	public class SourceReference
	{
		public unowned SourceFile file{ get; set; }
		public int first_line{ get; set; }
		public int last_line{ get; set; }
		public int first_column{ get; set; }
		public int last_column{ get; set; }

		~SourceReference ()
		{
			file = null;
		}
		
		public bool contains_position (int line, int column)
		{
			if ((this.first_line < line || ((line == this.first_line && column >= this.first_column) || this.first_column == 0))
			    && (line < this.last_line || ((line == this.last_line) || this.last_column == 0))) {
				return true;
			} else {
				return false;
			}
		}
		
		public bool contains_source_reference (SourceReference child)
		{
			if (this.first_line < child.first_line
			   || (this.first_line == child.first_line && this.first_column < child.first_column && this.first_column != 0 && child.first_column != 0)
			   || this.last_line > child.last_line
			   || (this.last_line == child.last_line && this.last_column  > child.last_column && this.last_column != 0 && child.last_column  != 0)) {
				return true;
			} else {
				return false;
			}
		}
	}
}
