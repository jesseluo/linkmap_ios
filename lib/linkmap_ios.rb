require "linkmap_ios/version"
require "json"

module LinkmapIos
  class LinkmapParser
    attr_reader :id_map
    attr_reader :library_map

    def initialize(file_path)
      @file_path = file_path
      @id_map = {}
      @library_map = {}
    end

    def hash
      # Cache
      if @result_hash
        return @result_hash
      end

      parse

      total_size = @library_map.map {|_, v| v.size }.inject(:+)
      detail = []
      @library_map.each_value do |lib|
        detail << {:library => lib.name, :size => lib.size, :objects => lib.objects.map {|o| @id_map[o][:object] }}
      end

      # puts total_size
      # puts detail

      @result_hash = {:total => total_size, :detail => detail}
      @result_hash
    end

    def json
      JSON.pretty_generate(hash)
    end

    def report()
      result = hash
      file = ''

      file << "# Total size\n"
      file << "#{result[:total]} Byte\n"
      file << "\n# Library detail\n"
      result[:detail].sort_by { |h| h[:size] }.each do |lib|
        file << "#{lib[:library]}   #{lib[:size]} Byte\n"
      end
      file << "\n# Object detail\n"
      @id_map.each_value do |id_info|
        file << "#{id_info[:object]}   #{id_info[:size]} Byte\n"
      end

      file
    end

    private

    def parse
      File.foreach(@file_path).with_index do |line, line_num|
        begin
          # Deal with string like 
          unless line.valid_encoding?
            line = line.encode("UTF-16", :invalid => :replace, :replace => "?").encode('UTF-8')
            # puts "#{line_num}: #{line}"
          end

          if line.include? "#"
            if line.include? "# Object files:"
              @subparser = :parse_object_files
            elsif line.include? "# Sections:"
              @subparser = :parse_sections
            elsif line.include? "# Symbols:"
              @subparser = :parse_symbols
            end
          else
            send(@subparser, line)
          end
        rescue => e
          puts "Exception on Link map file line #{line_num}. Content is"
          puts line
          raise e
        end
      end

      # puts @id_map
      # puts @library_map
    end

    def parse_object_files(text)
      if text =~ /\[(.*)\].*\/(.*)\((.*)\)/
        # Sample:
        # [  6] SomePath/Release-iphoneos/ReactiveCocoa/libReactiveCocoa.a(MKAnnotationView+RACSignalSupport.o)
        # So $1 is id. $2 is library
        id = $1.to_i
        @id_map[id] = {:library => $2, :object => $3}

        library = (@library_map[$2] or Library.new($2))
        library.objects << id
        @library_map[$2] = library
      elsif text =~ /\[(.*)\].*\/(.*)/
        # Sample:
        # System
        # [100] /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS9.3.sdk/System/Library/Frameworks//UIKit.framework/UIKit.tbd
        # Main
        # [  3] /SomePath/Release-iphoneos/CrashDemo.build/Objects-normal/arm64/AppDelegate.o
        id = $1.to_i
        lib = $2.end_with?('.tbd') ? 'System' : 'Main'
        @id_map[id] = {:library => lib, :object => $2}

        library = (@library_map[lib] or Library.new(lib))
        library.objects << id
        @library_map[lib] = library
      end
    end

    def parse_sections(text)
      # Do nothing
    end

    def parse_symbols(text)
      # Sample
      # 0x1000055C8	0x0000003C	[  4] -[FirstViewController viewWillAppear:]
      if text =~ /.*(0x.*)\s\[(.*\d)\].*/
        id_info = @id_map[$2.to_i]
        if id_info
          id_info[:size] = (id_info[:size] or 0) + $1.to_i(16)
          @library_map[id_info[:library]].size += $1.to_i(16)
        end
      end
    end
  end

  class Library
    attr_accessor :name
    attr_accessor :size
    attr_accessor :objects

    def initialize(name)
      @name = name
      @size = 0
      @objects = Array.new
    end

    def to_hash
      hash = {}
      instance_variables.each_with_object({}) { |var, hash| hash[var.to_s.delete("@")] = instance_variable_get(var) }
      hash
    end
  end
end
