class Common {
	public static string[] read_file(string filename) {
		string content;
		ulong length;
		
		try {
			FileUtils.get_contents(filename, out content, out length);
		} catch (FileError e) {
			error(e.message);
		}
		
		var lines = content.split("\n");
		
		return lines;
	}
	
	public static string[] read_file_without_comments(string filename) {
		try {
			var re_comment = new Regex("#.*");
		
			var lines = Common.read_file(filename);
			for(var i=0; i<lines.length; i++) {
				lines[i] = re_comment.replace(lines[i], lines[i].length, 0, "");
			}
			
			return lines;
		} catch (RegexError e) {
			error(e.message);
		}
	}
	
	public static void write_file(string filename, string content) {
		try {
			FileUtils.set_contents(filename, content, content.length);
		} catch (FileError e) {
			error(e.message);
		}
	}
}

class Parse {
	private static Gee.Map<string,string> types;
	private static Gee.Set<string> basic_types;
	
	private static Gee.Map<string,string> extensions;
	private static Gee.Map<string,string> enums_member_values;
	private static Gee.Map<string,Enum> enums;
	
	private static Gee.Map<string,Function> functions;
	
	private class Enum {
		public string name;
		public Gee.List<Member> members = new Gee.LinkedList<Member>();
		
		public class Member {
			public string name;
			public string val;
			
			public Member(string n, string v) {
				this.name = n;
				this.val = v;
			}
		}
		
		private Member parse_member(string line) {
			try {
				MatchInfo match;
				var name = "";
				var val = "";
				
				if(Regex.match_simple("^\\s+[0-9A-Z_]+.*=.*[Xx0-9A-F]+.*$", line)) {
					var re_name = new Regex("[0-9A-Z_]+");
					re_name.match(line, 0, out match);
					name = match.fetch(0);
					
					var re_value = new Regex("=.*[Xx0-9A-F]+");
					re_value.match(line, 0, out match);
					val = match.fetch(0).replace("=","").strip();
					if(!(enums_member_values.has_key(name))) {
						enums_member_values[name] = val;
					}
				} else if(Regex.match_simple("^\tuse ", line)) {
					var re_name = new Regex(" [0-9A-Z_]+\\s*$");
					re_name.match(line, 0, out match);
					name = match.fetch(0).strip();
					//val will be added later when all enums are parsed
				} else {
					error("Can't parse enum '%s'", line);
				}
				
				var member = new Member(name, val);
				this.members.add(member);
				
				return  member;
			} catch (RegexError e) {
				error(e.message);
			}
		}
		
		public Enum (Gee.List<string> lines) {
			try {
				MatchInfo match;
				string line;
				
				//parse name
				var re_name = new Regex("^[0-z_]+"); //TODO: parse the ones with "," in it
				line = lines[0];
				re_name.match(line, 0, out match);
				this.name = match.fetch(0);
				
				//parse members
				for(var i=1; i<lines.size; i++) {
					line = lines[i];
					parse_member(line);
				}
			} catch (RegexError e) {
				error(e.message);
			}
		}
	}
	
	private class Function {
		public string name;
		public string type;
		public Gee.List<Argument> arguments = new Gee.LinkedList<Argument>();
		
		public class Argument {
			public string name;
			public string type;
			public Flow flow;
			public Address address;
			public int size;
			
			public enum Flow {
				IN = 0,
				OUT = 1
			}
			
			public enum Address {
				VALUE = 0, //value
				VAR_ARRAY = 1, //array []
				CONST_ARRAY = 2, //array [34]
				REFERENCE = 3 //reference
			}
			
			public Argument(string n) {
					this.name = n;
					this.size = 0;
				}
			}
		
		public Argument parse_argument(string line) {
			try {
				MatchInfo match;
				
				//name
				var re_name = new Regex("[0-z]+");
				re_name.match(line, 0, out match);
				match.next();
				var argument = new Argument(match.fetch(0));
				
				//type
				var re_arg_desc = new Regex("[0-z]+ (in|out) .+");
				re_arg_desc.match(line, 0, out match);
				var arg_desc = match.fetch(0).split(" ");
				
				argument.type = arg_desc[0];
				if(argument.type != "void" && types.has_key(argument.type)) {
					argument.type = types[argument.type];
				} else if(type != "void") {
					error("Could not find return type for '%s'", argument.type);
				}
				
				//flow
				switch(arg_desc[1]) {
					case "in":
						argument.flow = Argument.Flow.IN;
						break;
					case "out":
						argument.flow = Argument.Flow.OUT;
						break;
					default:
						error("Could not find flow for '%s'", arg_desc[1]);
				}
				
				//address and size
				switch(arg_desc[2]) {
					case "value":
						if(argument.flow == Argument.Flow.OUT) {
							error("Flow of value can't be out");
						}
						argument.address = Argument.Address.VALUE;
						break;
					case "array":
						var re_const = new Regex("\\[[1-9][0-9]*\\]");
						var re_var = new Regex("\\[[0-z\\(\\)\\*/,]*\\]");
						if(re_const.match(arg_desc[3], 0, out match)) {
							argument.address = Argument.Address.CONST_ARRAY;
							argument.size = int.parse(match.fetch(0)[1:-1]);
						} else if(re_var.match(arg_desc[3], 0, out match)) {
							argument.address = Argument.Address.VAR_ARRAY;
						} else {
							error("Could not parse array '%s'", arg_desc[3]);
						}
						break;
					case "reference":
						argument.address = Argument.Address.REFERENCE;
						break;
					default:
						error("Could not parse argument '%s'", arg_desc[2]);
				}
				
				this.arguments.add(argument);
				
				return argument;
			} catch (RegexError e) {
				error(e.message);
			}
		}
		
		public Function(Gee.List<string> lines) {
			try {
				MatchInfo match;
				string line;
				
				//parse name
				var re_name = new Regex("^[0-z]+");
				line = lines[0];
				re_name.match(line, 0, out match);
				this.name = match.fetch(0);
				
				//parse additional information
				var re_desc = new Regex("[A-z]+");
				for(int i=1; i<lines.size; i++) {
					line = lines[i];
					re_desc.match(line, 0, out match);
					
					switch(match.fetch(0)) {
						case "return":
							var re_type = new Regex("[0-z]+$");
							re_type.match(line, 0, out match);
							
							this.type = match.fetch(0);
							if(type != "void" && types.has_key(type)) {
								this.type = types[type];
							} else if(type != "void") {
								error("Could not find return type for '%s'", type);
							}
							break;
						case "param":
							parse_argument(line);
							break;
						default:
							break;
					}
				}
			} catch (RegexError e) {
				error(e.message);
			}
		}
	}
	
	public static int run(string[] specs, string gl_header) {
		types = new Gee.HashMap<string,string>();
		basic_types = new Gee.HashSet<string>();
		
		extensions = new Gee.HashMap<string,string>();
		enums_member_values = new Gee.HashMap<string,string>();
		enums = new Gee.HashMap<string,Enum>();
		
		functions = new Gee.HashMap<string,Function>();
		
		//parse
		var gl_tm = specs[1];
		var gl_spec = specs[0];
		var enum_spec = specs[2];
		
		var gl_tm_lines = Common.read_file_without_comments(gl_tm);
		parse_gl_tm(gl_tm_lines);
		
		var gl_spec_lines = Common.read_file_without_comments(gl_spec);
		parse_gl_spec(gl_spec_lines);
		
		var enum_spec_lines = Common.read_file_without_comments(enum_spec);
		parse_enum_spec(enum_spec_lines);
		
		//generate
		string content = generate_header();
		Common.write_file(gl_header, content);
		
		return 0;
	}
	
	private static string mangle_type(string type) {
		var ret = type;
		
		/*if(type.length > 2 && type.substring(0,2) == "GL") {
			ret = type.slice(0,3).up() + type.substring(3);
		}*/
		
		return ret;
	}
	
	private static string mangle_function(string name) {
		var ret = name;
		
		ret = "gl" + ret;
		
		return ret;
	}
	
	private static string mangle_enum(string e) {
		var ret = e;
		
		ret = "GL_" + ret;
		
		return ret;
	}
	
	private static void parse_gl_tm (string[] lines) {
		try {
			MatchInfo match_desc;
			MatchInfo match_type;
			var re_desc = new Regex("^[0-z]+[ \\*]*(,\\*)*");
			var re_type = new Regex(",[\\s\\*0-z]+[ \\*,]+$");
			
			foreach(var line in lines) {
				if(re_desc.match(line, 0, out match_desc)) {
					if(re_type.match(line, 0, out match_type)) {
						var desc_array = match_desc.fetch(0).split(",");
						var type_array = match_type.fetch(0).substring(1).split(",");
						
						var desc = "";
						var type = "";
						for(var i=0; i<desc_array.length; i++) {
							desc += desc_array[i];
							type += type_array[i].replace("const","").strip();
							types[desc] = type;
						}
						
						var basic_type = type;
						while("*" in basic_type) {
							basic_type = basic_type.replace("*", "");
						}
						basic_type = basic_type.strip();
						if(basic_type.length > 0) { //for void -> *
							switch(basic_type) {
								case "GLUtesselator":
								case "GLUnurbs":
								case "GLUquadric":
								case "_GLfuncptr":
									break; //no functions using them
								default:
									basic_types.add(basic_type);
									break;
							}
						}
					}
				}
			}
			
			stdout.printf("Header: types parsed: %d\n", types.size);
		} catch (RegexError e) {
			error(e.message);
		}
	}
	
	private static void parse_gl_spec (string[] lines) {
		try {
			var re_func = new Regex("^[0-z_]+\\(.*\\)$");
			var re_func_desc = new Regex("^\t+.*$");
			
			var index = 0;
			while(index < lines.length) {
				var line = lines[index];
				
				if(line.length > 0) {
					if(re_func.match(line)) {
						var function_lines = new Gee.ArrayList<string>();
						
						function_lines.add(line);
						index++;
						line = lines[index];
						while(re_func_desc.match(line)) {
							function_lines.add(line);
							index++;
							line = lines[index];
						}
						
						var function = new Function(function_lines);
						functions.set(function.name, function);
						index--;
					}
				}
				index++;
			}
			
			stdout.printf("Header: functions parsed: %d\n", functions.size);
		} catch (RegexError e) {
			error(e.message);
		}
	}
	
	private static void parse_enum_spec(string[] lines) {
		try {
			var re_enum = new Regex("^[0-9A-Za-z]+[0-9A-Za-z_, ]*(enum:.*|[^:]*)$");
			var re_ext = new Regex("Extensions define:");
			
			var index = 0;
			while(index < lines.length) {
				var line = lines[index];
				
				if(line.length > 0) {
					if(re_enum.match(line)) {
						var enum_lines = new Gee.ArrayList<string>();
						enum_lines.add(line);
						
						index++;
						line = lines[index];
						while(index < lines.length && !re_enum.match(line)) {
							if(line.strip().length > 0) {
								enum_lines.add(line);
							}
							index++;
							line = lines[index];
						}
						
						var e = new Enum(enum_lines);
						enums.set(e.name, e);
						index--;
					} else if(re_ext.match(line)) {
						index++;
						line = lines[index];
						while(index < lines.length && !re_enum.match(line)) {
							if(line.strip().length > 0) {
								MatchInfo match;
								
								var re_name = new Regex("[0-9A-Za-z_]+");
								re_name.match(line, 0, out match);
								var name = match.fetch(0);
								
								var re_value = new Regex("=.*[Xx0-9A-F]+");
								re_value.match(line, 0, out match);
								var val = match.fetch(0).replace("=","").strip();
								extensions[name] = val;
							}
							
							index++;
							line = lines[index];
						}
						
						index --;
					}
				}
				
				index++;
			}
			
			var members_count = 0;
			
			foreach(var e in enums.values) {
				foreach(var member in e.members) {
					if(member.val.length == 0) {
						if(enums_member_values.has_key(member.name)) {
							member.val = enums_member_values[member.name];
						} else {
							//error("Enum '%s' not defined", member.name);
							continue; //Some are linked to but not defined
						}
					}
					members_count++;
				}
			}
			
			stdout.printf("Header: enums parsed: %d\n", enums.size);
			stdout.printf("Header: enums members parsed: %d\n", members_count);
		} catch (RegexError e) {
			error(e.message);
		}
	}
	
	private static string generate_header() {
		var content = "";
		
		//enums (defines)
		var enums_count = 0;
		
		content += "/* ENUMS */\n" +
				   "\n";
		
		foreach(var name in extensions.keys) {
			content += "#define %s %s\n".printf(mangle_enum(name), extensions[name]);
			enums_count ++;
		}
		
		content += "\n";
		
		foreach(var name in enums_member_values.keys) {
			content += "#define %s %s\n".printf(mangle_enum(name), enums_member_values[name]);
			enums_count++;
		}
		
		content += "\n";
		
		stdout.printf("Header: enums written: %d\n", enums_count);
		
		//types
		var types_count = 0;
		
		content += "/* TYPEDEFS */\n" +
				   "\n";
		
		//for ptrdiff_t, int64_t and uint64_t
		content += "#include <stddef.h>\n" +
				   "#include <inttypes.h>\n" +
				   "\n";
		
		foreach(var type in basic_types) {
			string type_name;
			
			switch(type) {
				case "GLchar":
				case "GLcharARB":
					type_name = "char";
					break;
				case "GLbyte":
					type_name = "signed char";
					break;
				case "GLboolean":
				case "GLubyte":
					type_name = "unsigned char";
					break;
				case "GLshort":
					type_name = "short";
					break;
				case "GLushort":
				case "GLhalfNV":
					type_name = "unsigned short";
					break;
				case "GLint":
				case "GLsizei":
					type_name = "int";
					break;
				case "GLuint":
				case "GLenum":
				case "GLhandleARB":
				case "GLbitfield":
					type_name = "unsigned int";
					break;
				case "GLint64":
				case "GLint64EXT":
					type_name = "int64_t";
					break;
				case "GLuint64":
				case "GLuint64EXT":
					type_name = "uint64_t";
					break;
				case "GLfloat":
				case "GLclampf":
					type_name = "float";
					break;
				case "GLdouble":
				case "GLclampd":
					type_name = "double";
					break;
				case "GLvoid":
					type_name = "void";
					break;
				case "GLintptr":
				case "GLsizeiptr":
				case "GLintptrARB":
				case "GLsizeiptrARB":
					type_name = "ptrdiff_t";
					break;
				case "GLvdpauSurfaceNV":
					type_name = "GLintptr";
					break;
				case "GLsync":
					type_name = "struct __GLsync *";
					content += "typedef %s%s;\n".printf(type_name, type);
					types_count++;
					continue;
				case "GLDEBUGPROCAMD":
				case "GLDEBUGPROCARB":
					type_name = "int"; //TODO: write proper type
					break;
				case "struct _cl_event":
				case "struct _cl_context":
					content += "%s;\n".printf(type);
					types_count++;
					continue;
				default:
					error("Type '%s' not covered\n", type);
			}
			
			content += "typedef %s %s;\n".printf(type_name, mangle_type(type));
			
			types_count++;
		}
		
		content += "\n";
		
		stdout.printf("Header: types written: %d\n", types_count);
		
		
		//functions
		var functions_count = 0;
		
		content += "/* FUNCTIONS */\n" +
				   "\n";
		
		foreach(var function in functions.values) {
			//arguments
			var args_str = "";
			var comment_args_str = "";
			
			foreach(var argument in function.arguments) {
				var arg_str = "";
				var comment_arg_str = "";
				
				switch(argument.address) {
					case Function.Argument.Address.VALUE:
						if(argument.flow == Function.Argument.Flow.IN) {
							arg_str = "%s %s".printf(mangle_type(argument.type), argument.name);
							comment_arg_str = " * @%s: (in):".printf(argument.name);
						} else {
							error("Flow of value can't be out");
						}
						break;
					case Function.Argument.Address.VAR_ARRAY:
						if(argument.flow == Function.Argument.Flow.IN) {
							arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
							comment_arg_str = " * @%s: (in) (array zero-terminated=1) (allow-none):".printf(argument.name);
						} else {
							arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
							comment_arg_str = " * @%s: (out caller-allocates) (array zero-terminated=1):".printf(argument.name);
						}
						break;
					case Function.Argument.Address.CONST_ARRAY:
						if(argument.size > 1) {
							if(argument.flow == Function.Argument.Flow.IN) {
								arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
								comment_arg_str = " * @%s: (in) (array fixed-size=%d) (allow-none):".printf(argument.name, argument.size);
							} else {
								arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
								comment_arg_str = " * @%s: (out caller-allocates) (array fixed-size=%d):".printf(argument.name, argument.size);
							}
						} else if(argument.size == 1) {
							if(argument.flow == Function.Argument.Flow.IN) {
								arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
								comment_arg_str = " * @%s: (in) (array fixed-size=%d) (allow-none):".printf(argument.name, argument.size);
							} else {
								arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
								comment_arg_str = " * @%s: (out caller-allocates) (array fixed-size=%d):".printf(argument.name, argument.size);
							}
						} else {
							error("No size given for const length array");
						}
						break;
					case Function.Argument.Address.REFERENCE:
						if(argument.flow == Function.Argument.Flow.IN) {
							arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
							comment_arg_str = " * @%s: (in):".printf(argument.name);
						} else {
							arg_str = "%s* %s".printf(mangle_type(argument.type), argument.name);
							comment_arg_str = " * @%s: (out caller-allocates):".printf(argument.name);
						}
						break;
				}
				
				args_str += arg_str + ", ";
				comment_args_str += comment_arg_str + "\n";
			}
			
			var transfer = " * Returns: (transfer full):\n";
			
			//gtk-doc coment
			content += ("/**\n" +
						" * %s:\n" +
						"%s" +
						"%s" +
						"*/\n").printf(
					mangle_function(function.name),
					comment_args_str,
					transfer);
			
			//function declaration
			if(args_str.length > 0) {
				args_str = args_str[0:-2];
			}
			
			content += "%s %s(%s);\n".printf(
					mangle_type(function.type),
					mangle_function(function.name),
					args_str);
			
			functions_count++;
		}
		
		content += "\n";
		
		stdout.printf("Header: functions written: %d\n", functions_count);
		
		return content;
	}
}

class Fix {
	public static int run(string gl_gir_temp, string gl_gir) {
		try {
			var gir_lines = Common.read_file(gl_gir_temp);
			
			var new_content = new StringBuilder();
			var re_constants = new Regex("<constant name=");
			var re_constant_name = new Regex("name=\"[^\"]*\"");
			
			foreach(var line in gir_lines) {
				if(re_constants.match(line)) {
					MatchInfo match;
					var new_line = "";
					
					re_constant_name.match(line, 0, out match);
					var name = match.fetch(0).replace("name=","");
					
					new_line = line[0:line.index_of(name)+name.length] +
							" c:identifier=%s".printf(name) +
							line.substring(line.index_of(name)+name.length);
					
					new_content.append(new_line + "\n");
				} else {
					new_content.append(line + "\n");
				}
			}
			
			var content = new_content.str;
			
			content = content.replace("libGL.so.1","libGL");
			content = content.replace("c:identifier-prefixes=\"\"","c:identifier-prefixes=\"GL\"");
			content = content.replace("c:symbol-prefixes=\"\"","c:symbol-prefixes=\"gl\"");
			
			content = content.replace("<type c:type=\"int64_t\"/>", "<type name=\"gint64\" c:type=\"int64_t\"/>");
			content = content.replace("<type c:type=\"uint64_t\"/>", "<type name=\"guint64\" c:type=\"uint64_t\"/>");
			content = content.replace("<type c:type=\"ptrdiff_t\"/>", "<type name=\"gsize\" c:type=\"ptrdiff_t\"/>");
			
			content = content.replace("introspectable=\"0\"", "");
			
			Common.write_file(gl_gir, content);
			
			return 0;
		} catch (RegexError e) {
			error(e.message);
		}
	}
}

class Generate {
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] filenames;
	private static string gl_header;
	private static string gl_gir;
	private static bool parse = false;
	private static bool fix = false;
	
	private const OptionEntry[] options = {
		{ "", 0, 0, OptionArg.FILENAME_ARRAY, out filenames, "List of files", "FILE..." },
		{ "header", 0, 0, OptionArg.NONE, out parse, "Create header", null },
		{ "fix-gir", 0, 0, OptionArg.NONE, out fix, "Fix gir file", null },
		{ "", 'h', 0, OptionArg.FILENAME, out gl_header, "header file", null },
		{ "", 'g', 0, OptionArg.FILENAME, out gl_gir, "gir file", null },
		{ null }
	};
	
	public static int main(string[] args) {
		//parse args
		var opt_context = new OptionContext("- generate gir");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		
		try {
			opt_context.parse(ref args);
		} catch(Error e) {
			error(e.message);
		}
		
		//run selected operation
		if(parse) {
			Parse.run(filenames, gl_header);
			stdout.printf("Header: Generated header and saved it to '%s'.\n", gl_header);
		} else if(fix) {
			Fix.run(filenames[0], gl_gir);
			stdout.printf("Fix gir: Gir file '%s' fixed and saved to '%s'.\n", filenames[0], gl_gir);
		} else {
			error("Program error");
		}
		
		return 0;
	}
}
