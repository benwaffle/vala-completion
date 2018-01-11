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
using Vala;

namespace Afrodite
{
	public class CompletionEngine : Object
	{
		public string id;
		public signal void begin_parsing (CompletionEngine sender);
		public signal void end_parsing (CompletionEngine sender);
		public signal void file_removed (CompletionEngine sender, string filename);
		public signal void file_parsed (CompletionEngine sender, string filename, ParseResult parse_result);

		private Vala.List<string> _vapidirs;
		private Vala.List<SourceItem> _source_queue;
		
		private Mutex _source_queue_mutex;

		private bool _begin_parse_event_fired = false;
		
		private unowned Thread<int> _parser_thread;
		private int _parser_stamp = 0;
		private int _parser_remaining_files = 0;
		private int _current_parsing_total_file_count = 0;
		private bool _glib_init = false;
		private bool _is_parsing = false;

		private CodeDom _codedom;
		private GLib.AsyncQueue<ParseResult> _parse_result_list = new GLib.AsyncQueue<ParseResult> ();
		private uint _idle_id = 0;

		public CompletionEngine (string? id = null)
		{
			if (id == null)
				id = "";
				
			this.id = id;
			_vapidirs = new ArrayList<string> (GLib.str_equal);
			_source_queue = new ArrayList<SourceItem> ();
			_source_queue_mutex = new Mutex ();
			
			_codedom = new CodeDom ();
		}
		
		~Completion ()
		{
			Utils.trace ("Completion %s destroy", id);
			// invalidate the ast so the parser thread will exit asap
			_codedom = null;

			if (AtomicInt.@get (ref _parser_stamp) != 0) {
				Utils.trace ("join the parser thread before exit");
				_parser_thread.join ();
			}
			_parser_thread = null;
			if (_idle_id != 0) {
				Source.remove (_idle_id);
				_idle_id = 0;
			}
			Utils.trace ("Completion %s destroyed", id);
		}

		public bool is_parsing
		{
			get {
				return _is_parsing;
			}
		}

		public void add_vapi_dir (string path)
		{
			_vapidirs.add (path);
		}
		
		public void remove_vapi_dir (string path)
		{
			if (!_vapidirs.remove (path))
				warning ("remove_vapi_dir: vapidir %s not found", path);
		}
		
		public void queue_source (SourceItem item)
		{
			var sources = new ArrayList<SourceItem> ();
			sources.add (item.copy ());
			queue_sources (sources);
		}

		private SourceItem? source_queue_contains (SourceItem value)
		{
			foreach (SourceItem source in _source_queue) {
 				if (source.path == value.path) {
 					return source;
 				}
			}
			
			return null;
		}

		public bool queue_sources (Vala.List<SourceItem> sources, bool no_update_check = false)
		{
			bool result = false;
			
			_source_queue_mutex.@lock ();
			if (!_glib_init) {
				// merge standard base vapi (glib and gobject)
				_glib_init = true;
				string[] packages = new string[] { "glib-2.0", "gobject-2.0" };
				var context = new CodeContext ();
				
				foreach (string package in packages) {
					var paths = Utils.get_package_paths (package, context);
					if (paths != null) {
						foreach (string path in paths) {
							var item = new SourceItem (path);
							item.content = null;
							item.is_glib = true;
							sources.insert (0, item);
						}
					}
				}
			}
			foreach (SourceItem source in sources) {
				bool skip_unchanged_file = false;

				// test if file is really changed but only if it's not a live buffer
				if (no_update_check == false && source.content == null && _codedom != null) {
					var sf = _codedom.lookup_source_file (source.path);
					if (sf != null && sf.update_last_modification_time ()) {
						Utils.trace ("engine %s: skip unchanged source %s", id, source.path);
						skip_unchanged_file = true;
					}
				}

				if (!skip_unchanged_file)
				{
					var item = source_queue_contains (source);
					if (item == null || item.content != source.content) {
					/*
						if (source.content == null || source.content == "")
							Utils.trace ("%s: queued source %s. sources to parse %d", id, source.path, source_queue.size);
						else
							Utils.trace ("%s: queued live buffer %s. sources to parse %d", id, source.path, source_queue.size);
					*/	
						if (item != null)
							_source_queue.remove (item);

						_source_queue.add (source.copy ());
					} 
					else if (item.content == null && source.content != null) {
						item.content = source.content;
						//Utils.trace ("%s: updated live buffer %s. sources to parse %d", id, source.path, source_queue.size);
					}
				}
			}
			_source_queue_mutex.@unlock ();
			
			if (AtomicInt.compare_and_exchange (ref _parser_stamp, 0, 1)) {
				create_parser_thread ();
			} else {
				AtomicInt.inc (ref _parser_stamp);
			}
			
			return result;
		}
		
		public void queue_sourcefile (string path, string? content = null, bool is_vapi = false, bool is_glib = false)
		{
			var sources = new ArrayList<string> ();
			sources.add (path);
			
			queue_sourcefiles (sources, content, is_vapi);
		}

		public void queue_sourcefiles (Vala.List<string> paths, string? content = null, bool is_vapi = false, bool is_glib = false)
		{
			var sources = new ArrayList<SourceItem> ();
			
			foreach (string path in paths) {
				var item = new SourceItem (path);
				item.content = content;
				item.is_glib = is_glib;
				sources.add (item);
			}
			
			queue_sources (sources);
		}

		public void remove_source_filename (string source_path)
		{
#if DEBUG
                        GLib.Timer timer = new GLib.Timer ();
                        double start_time = 0;

                        timer.start ();
			Utils.trace ("engine %s: removing source %s", id, source_path);
			start_time = timer.elapsed ();
#endif

                        var source = _codedom.lookup_source_file (source_path);
                        assert (source != null);
                        _codedom.remove_source (source);

			this.file_removed (this, source_path);
#if DEBUG
			Utils.trace ("engine %s: removing source %s done %g", id, source_path, timer.elapsed () - start_time);
#endif
		}

		public CodeDom codedom
		{
			get {
				return _codedom;
			}
		}

		private void create_parser_thread ()
		{				
			try {
				if (_parser_thread != null) {
					_parser_thread.join ();
				}
				_parser_thread = Thread.create_full<int> (this.parse_sources, 0, true, false, ThreadPriority.LOW);
			} catch (ThreadError err) {
				error ("%s: can't create parser thread: %s", id, err.message);
			}
		}

		private int parse_sources ()
		{
#if DEBUG
			GLib.Timer timer = new GLib.Timer ();
			double start_time = 0;
			timer.start ();
#endif
			Utils.trace ("engine %s: parser thread *** starting ***...", id);

			Vala.List<SourceItem> sources = new ArrayList<SourceItem> ();

			while (true) {
				int stamp = AtomicInt.get (ref _parser_stamp);
				// set the number of sources to process
				AtomicInt.set (ref _parser_remaining_files, _source_queue.size );
				// get the source to parse
				_source_queue_mutex.@lock ();
				foreach (SourceItem item in _source_queue) {
					sources.add (item.copy ());
				}

				Utils.trace ("engine %s: queued %d", id, sources.size);
				AtomicInt.set (ref _current_parsing_total_file_count, sources.size);
				
				_source_queue.clear ();
				_source_queue_mutex.@unlock ();

				foreach (SourceItem source in sources) {
#if DEBUG
					Utils.trace ("engine %s: parsing source: %s", id, source.path);
					start_time = timer.elapsed ();
#endif

					Parser p = new Parser.with_source (source);
					var parse_results = p.parse ();
					_parse_result_list.@lock ();
					_parse_result_list.push_unlocked (parse_results);
					if (_idle_id == 0) {
						//_idle_id = Idle.add (this.on_parse_results, Priority.LOW);
						_idle_id = Timeout.add (250, this.on_parse_results, Priority.LOW);
					}
					_parse_result_list.unlock ();
#if DEBUG
					Utils.trace ("engine %s: parsing source: %s done %g", id, source.path, timer.elapsed () - start_time);
#endif
					AtomicInt.add (ref _parser_remaining_files, -1);
				}

				sources.clear ();

				//check for changes or exit request
				if (_codedom == null || AtomicInt.compare_and_exchange (ref _parser_stamp, stamp, 0)) {
					break;
				}
			}

			// clean up and exit
			AtomicInt.set (ref _current_parsing_total_file_count, 0);
			sources = null;

#if DEBUG
			timer.stop ();
			Utils.trace ("engine %s: parser thread *** exiting *** (elapsed time parsing %g)...", id, timer.elapsed());
#endif
			return 0;
		}

		private void on_begin_parsing ()
		{
			if (!_is_parsing) {
				_is_parsing = true;
				begin_parsing (this);
			}
		}

		private void on_end_parsing ()
		{
			if (AtomicInt.@get (ref _current_parsing_total_file_count) == 0) {
				_is_parsing = false;
				end_parsing (this);
			}
		}

		private bool on_parse_results ()
		{
			ParseResult? parse_result = null;

			_parse_result_list.@lock();
			parse_result = _parse_result_list.try_pop_unlocked ();
			if (parse_result == null) {
				// Tell to the parser thread that a new Idle should be created
				// for the merge process
				_idle_id = 0;
			}
			_parse_result_list.@unlock();
			
			// schedule the merge if required
			if (parse_result != null) {
				if (!_begin_parse_event_fired) {
					_begin_parse_event_fired = true;
					on_begin_parsing();
				}
				merge_and_resolve.begin (parse_result, this.on_merge_and_resolve_ended);
			} else {
				// this is the last run after the merge
				on_end_parsing ();
				_begin_parse_event_fired = false;
			}

			return false;
		}

		private void on_merge_and_resolve_ended (GLib.Object? source, GLib.AsyncResult r)
		{
			merge_and_resolve.end (r);
			_idle_id = Idle.add (this.on_parse_results, Priority.LOW);
			//_idle_id = Timeout.add (250, this.on_parse_results, Priority.LOW);
		}

		private async void merge_and_resolve (ParseResult result)
		{
			Utils.trace ("engine %s: async merge and resolve: %s", id, result.source_path);
			foreach (Vala.SourceFile s in result.context.get_source_files ()) {
				if (s.filename == result.source_path) {
					var ast_source = _codedom.lookup_source_file (result.source_path);
					bool source_exists = ast_source != null;
					bool need_update = true;

					// if I already parsed this source and this copy is a live gedit buffer
					// and the parsing contains some error, I maintain the previous copy in the ast
					if (!(source_exists && result.is_edited && result.error_messages.size > 0))
					{
						// if the source was already parsed and it's not opend in a edit window
						if (source_exists && !result.is_edited) {
							need_update = ast_source.update_last_modification_time();
						}
						// this is important!
						// TODO: we shouldn't hold this reference lookup_source_file should return an unowned ref
						ast_source = null;
						if (need_update) {
							yield perform_merge_and_resolve (s, result, source_exists);
						}
					} else {
						Utils.trace ("engine %s: source (live buffer) with errors mantaining the previous parsing: %s", id, result.source_path);
					}
					this.file_parsed (this, result.source_path, result);
					break; // found the file
				}
			}
			
			//return result;
		}

		private async void perform_merge_and_resolve (Vala.SourceFile s, ParseResult result, bool source_exists)
		{
			yield merge_vala_source (s, result, source_exists);
			yield resolve_codedom ();
		}
		
		private async void merge_vala_source (Vala.SourceFile s, ParseResult result, bool source_exists)
		{
#if DEBUG
			GLib.Timer timer = new GLib.Timer ();
			double start_time = 0, elapsed;
			timer.start ();
#endif
			var merger = new AstMerger (_codedom);
			if (source_exists) {
#if DEBUG
				Utils.trace ("engine %s: removing source (%p) %s", id, result, result.source_path);
				start_time = timer.elapsed ();
#endif
				remove_source_filename (result.source_path);
#if DEBUG
				Utils.trace ("engine %s: removing source (%p) %s done %g", id, result, result.source_path, timer.elapsed () - start_time);
#endif
			}
#if DEBUG
			Utils.trace ("engine %s: merging source %s", id, result.source_path);
			start_time = timer.elapsed ();
#endif
			yield merger.merge_vala_context (s, result.context, result.is_glib, result.is_edited);
			result.context = null; // let's free some memory
			merger = null;
#if DEBUG
			elapsed = timer.elapsed () - start_time;
			Utils.trace ("engine %s: merging source %s done %g %s", id, result.source_path, elapsed, elapsed > 0.7 ? " <== Warning" : "");
#endif
		}
		
		private async void resolve_codedom ()
		{
#if DEBUG
			GLib.Timer timer = new GLib.Timer ();
			double start_time = 0;
			timer.start ();
			//_codedom.dump_symbols ();
			Utils.trace ("engine %s: resolving ast", id);
			start_time = timer.elapsed ();
#endif
			var resolver = new SymbolResolver ();
			resolver.resolve (_codedom);
#if DEBUG
			Utils.trace ("engine %s: resolving ast done %g", id, timer.elapsed () - start_time);
#endif
		}
	}
}
