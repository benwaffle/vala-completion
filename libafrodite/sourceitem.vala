/* sourceitem.vala
 *
 * Copyright (C) 2010  Andrea Del Signore
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
	public enum SourceType
	{
		AUTO,
		VALA,
		GENIE,
		VAPI,
		UNKNOWN
	}

	public class SourceItem
	{
		private string _path;

		public string content;
		public SourceType source_type = SourceType.AUTO;
		public bool is_glib = false;
		public CodeContext context = null;

		public string path {
			get {
				return _path;
			}
		}

		public SourceItem (string? path, SourceType source_type = SourceType.AUTO)
		{
			if (path == null && source_type == SourceType.AUTO) {
				critical ("You have to specified either a path or a source_type");
			}

			this._path = path;
			if (source_type == SourceType.AUTO) {
				this.source_type = SourceItem.get_source_type (_path);
				if (this.source_type == SourceType.UNKNOWN) {
					critical ("Cannot determine the source type");
				}
			} else {
				this.source_type = source_type;
			}
		}

		public SourceItem copy ()
		{
			var item = new SourceItem(this.path, this.source_type);

			item.content = content;
			item.is_glib = is_glib;
			return item;
		}

		public static SourceType get_source_type (string path)
		{
			SourceType result;
			if (path.has_suffix (".vapi")) {
				result = SourceType.VAPI;
			} else if (path.has_suffix (".gs")) {
				result = SourceType.GENIE;
			} else if (path.has_suffix (".vala")) {
				result = SourceType.VALA;
			} else {
				result = SourceType.UNKNOWN;
			}
			return result;
		}
	}
}

