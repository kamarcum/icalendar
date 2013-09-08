=begin
  Copyright (C) 2008 Rick (http://github.com/rubyredrick)

  This library is free software; you can redistribute it and/or modify it
  under the same terms as the ruby language itself, see the file COPYING for
  details.
=end

require 'date'
require 'uri'
require 'stringio'

module Icalendar

  # This class is not yet fully functional..
  #
  # Gem versions < 1.1.0.0 used to return a string for the recurrence_rule component,
  # but now it returns this Icalendar::RRule class. ie It's not backwards compatible!
  #
  # To get the original RRULE value from a parsed feed, use the 'orig_value' property.
  #
  # Example:
  #   rules = event.recurrence_rules.map{ |rule| rule.orig_value }
  
  class RRule < Icalendar::Base
    
    class Weekday
      def initialize(day, position)
        @day, @position = day, position
      end
      
      def to_s
        "#{@position}#{@day}"
      end
    end

    attr_accessor :frequency, :until, :count, :interval, :by_list, :wkst

    def initialize(name, params, value)
      @value = value
      frequency_match = value.match(/FREQ=(SECONDLY|MINUTELY|HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY)/)
      @frequency = frequency_match[1]
      @until = parse_date_val("UNTIL", value)
      @count = parse_int_val("COUNT", value)
      @interval = parse_int_val("INTERVAL", value)
      @by_list = {:bysecond => parse_int_list("BYSECOND", value)}
      @by_list[:byminute] = parse_int_list("BYMINUTE",value)
      @by_list[:byhour] = parse_int_list("BYHOUR", value)
      @by_list[:byday] = parse_weekday_list("BYDAY", value)
      @by_list[:bymonthday] = parse_int_list("BYMONTHDAY", value)
      @by_list[:byyearday] = parse_int_list("BYYEARDAY", value)
      @by_list[:byweekno] = parse_int_list("BYWEEKNO", value)
      @by_list[:bymonth] = parse_int_list("BYMONTH", value)
      @by_list[:bysetpos] = parse_int_list("BYSETPOS", value)
      @wkst = parse_wkstart(value)
    end
    
    # Returns the original pre-parsed RRULE value.
    def orig_value
      @value
    end

    def to_ical
      raise Icalendar::InvalidPropertyValue.new("FREQ must be specified for RRULE values") unless frequency
      raise Icalendar::InvalidPropertyValue.new("UNTIL and COUNT must not both be specified for RRULE values") if [self.until, count].compact.length > 1
      result = ["FREQ=#{frequency}"]
      result << "UNTIL=#{self.until.to_ical}" if self.until
      result << "COUNT=#{count}" if count
      result << "INTERVAL=#{interval}" if interval
      by_list.each do |key, value|
        if value
          if key == :byday
            result << "BYDAY=#{value.join ','}"
          else
            result << "#{key.to_s.upcase}=#{value}"
          end
        end
      end
      result << "WKST=#{wkst}" if wkst
      result.join ';'
    end
    
    def parse_date_val(name, string)
      match = string.match(/;#{name}=(.*?)(;|$)/)
      match ? DateTime.parse(match[1]) : nil
    end
    
    def parse_int_val(name, string)
      match = string.match(/;#{name}=(\d+)(;|$)/)
      match ? match[1].to_i : nil
    end
    
    def parse_int_list(name, string)
      match = string.match(/;#{name}=([+-]?.*?)(;|$)/)
      if match
        match[1].split(",").map {|int| int.to_i}
      else
        nil
      end
    end
    
    def parse_weekday_list(name, string)
      match = string.match(/;#{name}=(.*?)(;|$)/)
      if match
        return_array = match[1].split(",").map do |weekday|
          wd_match = weekday.match(/([+-]?\d*)(SU|MO|TU|WE|TH|FR|SA)/)
          Weekday.new(wd_match[2], wd_match[1])
        end
      else
        nil
      end
      return_array
    end

    def parse_wkstart(string)
      match = string.match(/;WKST=(SU|MO|TU|WE|TH|FR|SA)(;|$)/)
      if match
        match[1]
      else
        nil
      end
    end
    
    # TODO: Incomplete
    def occurrences_of_event_starting(event, datetime)
      initial_start = event.dtstart
      (0...count).map do |day_offset|
        occurrence = event.clone
        occurrence.dtstart = initial_start + day_offset
        occurrence.clone
      end
    end

    def occurrences_of_event_between(event, start_time, end_time)
      current_time = first_start_of_event_between(event, start_time, end_time)
      current_end_time = event.dtend.to_datetime
      return [] unless current_time
      start_datetime = start_time.to_datetime
      end_datetime = end_time.to_datetime
      occurrences = []
      while current_time <= end_datetime
        occurrence = event.clone
        occurrence.dtstart = current_time
        occurrence.dtend = current_end_time
        occurrences << occurrence
        current_time = add_frequency_to_datetime(current_time)
        current_end_time = add_frequency_to_datetime(current_end_time)
      end
      occurrences
    end

    private
    def first_start_of_event_between(event, start_time, end_time)
      current_time = event.dtstart.to_datetime
      cutoff = @until
      start_datetime = start_time.to_datetime
      end_datetime = end_time.to_datetime
      if cutoff.nil? && @count
        cutoff = add_frequency_to_datetime(current_time, @count)
      elsif cutoff.nil?
        cutoff = current_time + 126230400 # ~4 years
      end
      if current_time.between? start_datetime, end_datetime
        current_time
      else
        while current_time.between? start_datetime, cutoff
          current_time = add_frequency_to_datetime(current_time)
          if current_time.between? start_datetime, end_datetime
            return current_time
          end
        end
        nil
      end
    end

    def add_frequency_to_datetime start, times=1
      case frequency
      when "SECONDLY"
        start + times/86400.0
      when "MINUTELY"
        start + times/1440.0
      when "HOURLY"
        start + times/24.0
      when "DAILY"
        start + times
      when "WEEKLY"
        start + 7 * times
      when "MONTHLY"
        sum = start.month + times
        month = (sum % 12 == 0) ? 12 : sum % 12
        Time.utc(start.year, month, start.day, start.hour, start.minute, start.second).to_datetime
      when "YEARLY"
        Time.utc(start.year + times, start.month, start.day, start.hour, start.minute, start.second).to_datetime
      end
    end
  end
end
