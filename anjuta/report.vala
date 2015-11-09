/*
 * Copyright (C) 2008-2009 Abderrahim Kitouni
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

 /* A Vala.Report subclass for reporting errors in Anjuta UI */
public class AnjutaReport : Vala.Report {
	struct Error {
		public Vala.SourceReference source;
		public bool error;
		public string message;
	}
	public IAnjuta.DocumentManager docman { get; set; }
	Vala.List<Error?> errors_list = new Vala.ArrayList<Error?>();
	bool general_error = false;

	public void update_errors (IAnjuta.Editor editor) {
		var ind = editor as IAnjuta.Indicable;
		var mark = editor as IAnjuta.Markable;
		if (ind == null && mark == null)
			return;

		if (ind != null)
			ind.clear ();
		if (mark != null)
			mark.delete_all_markers (IAnjuta.MarkableMarker.MESSAGE);

		foreach (var e in errors_list) {
			if (e.source.file.filename.has_suffix (((IAnjuta.Document)editor).get_filename ())) {
				if (ind != null) {
					/* begin_iter should be one cell before to select the first character */
					var begin_iter = editor.get_line_begin_position (e.source.begin.line);
					for (var i = 1; i < e.source.begin.column; i++)
						begin_iter.next ();
					var end_iter = editor.get_line_begin_position (e.source.end.line);
					for (var i = 0; i < e.source.end.column; i++)
						end_iter.next ();
					ind.set(begin_iter, end_iter, e.error ? IAnjuta.IndicableIndicator.CRITICAL :
					                                        IAnjuta.IndicableIndicator.WARNING);
				}
				if (editor is IAnjuta.Markable) {
					mark.mark(e.source.begin.line, IAnjuta.MarkableMarker.MESSAGE, e.message);
				}
			}

		}
	}
	public void clear_error_indicators (Vala.SourceFile? file = null) {
		if (file == null) {
			errors_list = new Vala.ArrayList<Error?>();
			errors = 0;
		} else {
			for (var i = 0; i < errors_list.size; i++) {
				if (errors_list[i].source.file == file) {
					if (errors_list[i].error)
						errors --;
					else
						warnings --;

					errors_list.remove_at (i);
					i --;
				}
			}
			assert (errors_list.size <= errors + warnings);
		}

		foreach (var doc in docman.get_doc_widgets ()) {
			if (doc is IAnjuta.Indicable)
				((IAnjuta.Indicable)doc).clear ();
			if (doc is IAnjuta.Markable)
				((IAnjuta.Markable)doc).delete_all_markers (IAnjuta.MarkableMarker.MESSAGE);
		}
	}
	public override void warn (Vala.SourceReference? source, string message) {
		warnings ++;

		if (source == null)
			return;

		lock (errors_list) {
			errors_list.add(Error () {source = source, message = message, error = false});
		}
	}
	public override void err (Vala.SourceReference? source, string message) {
		errors ++;

		if (source == null) {
			general_error = true;
			return;
		}

		lock (errors_list) {
			errors_list.add(Error () {source = source, message = message, error = true});
		}
	}
}
