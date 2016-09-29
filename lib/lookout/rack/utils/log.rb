require 'rubygems'
require 'log4r'
require 'singleton'
require 'time'
require 'configatron'

module Lookout::Rack::Utils
  # Logging.  Logs to log/<project_name>.log with the format:
  #
  #   [Log Level]: [Timestamp (ISO-8601)]: [File:linenum]: [Log Message]
  #
  # Use through the helper:
  #   log.warn 'This is my log message'
  #
  class Log
    include Singleton
    include Log4r

    # Formatter that include the filename and relative path, and line number in
    # output of the caller.
    #
    # Since all callers go through the methods defined in this class to log, we
    # look at the second line of the tracer output, removing everything but the
    # directories after the project directory.
    #
    class LookoutFormatter < Log4r::Formatter
      # Return the project base directory for filtering to help with
      # identifiying the filename and line number when formatting the log
      # message
      #
      # @return [String] Base directory for the project
      def basedir
        @basedir ||= File.expand_path(File.join(File.dirname(__FILE__), ".."))
      end

      # Return the common base directory between this project and the
      # given trace. If no common base directory is found, return
      # basedir.
      #
      # This memoizes the result, which can be bad if the first log
      # comes from an unusual place. However, in all current uses this
      # is running from an unpacked jar/war and its vastly faster to
      # memoize the result.
      #
      # @param [String] tracer A line from the LogEvent#tracer Array
      # @return [String] Common base directory with the trace
      def common_basedir(tracer)
        return @common_basedir if @common_basedir

        basedir_pieces = basedir.split(File::SEPARATOR)
        trace_pieces = tracer.split(File::SEPARATOR)
        i = 0
        while basedir_pieces[i] == trace_pieces[i]
          i += 1
        end
        # If there were no common directories (besides /), return our basedir
        @common_basedir = (i <= 1) ? basedir : basedir_pieces[0...i].join(File::SEPARATOR)
      end

      # Return a trimmed version of the filename from where a LogEvent occurred
      # @param [String] tracer A line from the LogEvent#tracer Array
      # @return [String] Trimmed and parsed version of the file ane line number
      def event_filename(tracer)
        base = common_basedir(tracer)
        parts = tracer.match(/#{base}\/(.*:[0-9]+).*:/)

        # If we get no matches back, we're probably in a jar file in which case
        # the format of the tracer is going to be abbreviated
        if parts.nil?
          parts = tracer.match(/(.*:[0-9]+).*:/)
        end
        return parts[-1] if parts
      end

      # Receive the LogEvent and pull out the log message and format it for
      # display in the logs
      #
      # @param [Log4r::LogEvent] event
      # @return [String] Formatted log message
      def format(event)
        filename = event_filename(event.tracer[1])
        # CCYY-MM-DDThh:mm:ss.sssTZD
        time = Time.now.utc.iso8601 3
        return "#{Log4r::LNAMES[event.level]}: #{time}: #{filename}: #{event.data}\n"
      end
    end


    attr_reader :outputter

    def initialize
      logger_name = configatron.project_name.to_s.gsub(/\s*/, '_')
      if logger_name.nil? || logger_name.empty?
        logger_name = 'no_name_given'
      end

      @logger = Logger.new(logger_name)

      if configatron.logging.enabled
        index = Log4r::LNAMES.index(configatron.logging.level)
        # if logger.level is not in LNAMES an exception will be thrown
        @logger.level = index unless index.nil?
      else
        @logger.level = Log4r::OFF
      end

      @outputter = build_outputter(logger_name)
      @logger.trace = true
      @outputter.formatter = LookoutFormatter
      @logger.outputters = @outputter
    end


    [:debug, :info, :warn, :error, :fatal, :level].each do |method|
      define_method(method) do |*args, &block|
        if defined?(Lookout::Rack::Utils::Graphite)
          unless method == :level
            Lookout::Rack::Utils::Graphite.increment("log.#{method}") unless (configatron.statsd.exclude_levels || []).include?(method)
          end
        end
        @logger.send(method, *args, &block)
      end

      # Returns true iff the current severity level allows for
      # the printing of level messages.
      allow_logging = "#{method}?".to_sym
      define_method(allow_logging) do |*args|
        @logger.send(allow_logging, *args)
      end
    end

    # Build and return the appropriate Outputter
    def build_outputter(logger_name)
      if configatron.logging.file =~ /^stdout$/i
        StdoutOutputter.new("#{logger_name}stdout")
      else
        FileOutputter.new("#{logger_name}fileoutput",
                          {:filename => configatron.logging.file,
                           :trunc => false})
      end
    end
    private :build_outputter
  end
end
