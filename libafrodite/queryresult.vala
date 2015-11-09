/* queryresult.vala
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
	public class QueryResult
	{
		public Vala.List<ResultItem> children {
			get{ return _children; }
			set{ _children = value; }
		}
		private Vala.List<ResultItem> _children = new Vala.ArrayList <ResultItem> ();
		public int items_created = 0;
		
		public bool is_empty
		{
			get {
				return children.size == 0;
			}
		}
		
		public void add_result_item (ResultItem item)
		{
			children.add (item);
		}

		public ResultItem new_result_item (ResultItem? parent, Afrodite.Symbol symbol)
		{
			var res = new ResultItem ();
			res.symbol = symbol;
			res.parent = parent;
			items_created++;
			
			return res;
		}
		
		~Result ()
		{
			children = null;
		}
	}
}
