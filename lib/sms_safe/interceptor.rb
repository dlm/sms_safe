require 'mail'

module SmsSafe

  # Main class with almost all the functionality.
  # When a message is intercepted, Interceptor decides whether we need to do anything with it,
  #   and does it.
  # The different adaptor classes in the Interceptors module provide mapping to each of the SMS libraries peculiarities.
  class Interceptor

    # Method called by all the sub-classes to process the SMS being sent
    # @param [Object] original_message the message we intercepted from the texter gem. May be of varying types, depending
    #   on which texter gem is being used.
    # @return [Object] the message to send (if modified recipient / text), of the same type we received
    #   or nil if no SMS should be sent
    def process_message(original_message)
      message = convert_message(original_message)

      if intercept_message?(message)
        intercept_message!(message)
      else
        original_message
      end
    end

    # Decides whether to intercept the message that is being sent, or to let it go through
    # @param [Message] message the message we are evaluating
    # @return [Boolean] whether to intercept the message (true) or let it go through (false)
    def intercept_message?(message)
      matching_rules = [SmsSafe.configuration.internal_phone_numbers].flatten.compact
      internal_recipient = matching_rules.any? do |rule|
        case rule
          when String then message.to == rule
          when Regexp then !!(message.to =~ rule)
          when Proc   then rule.call(message)
          else
            raise InvalidConfigSettingError.new("Ensure internal_phone_numbers is a String, a Regexp or a Proc (or an array of them). It was: #{SmsSafe.configuration.internal_phone_numbers.inspect}")
        end
      end
      !internal_recipient # Intercept messages that are *not* going to one of the allowed numbers
    end

    # Once we've decided to intercept the message, act on it, based on the intercept_mechanism set
    # @param [Message] message the message we are evaluating
    # @return [Object] the message to send, of the type that corresponds to the texter gem (if :redirecting)
    #   or nil to cancel sending (if :email or :discard)
    def intercept_message!(message)
      case SmsSafe.configuration.intercept_mechanism
        when :redirect then redirect(message)
        when :email then email(message)
        when :discard then discard
        else
          raise InvalidConfigSettingError.new("Ensure intercept_mechanism is either :redirect, :email or :discard. It was: #{SmsSafe.configuration.intercept_mechanism.inspect}")
      end
    end

    # Decides which phone number to redirect the message to
    # @param [Message] message the message we are redirecting
    # @return [String] the phone number to redirect the number to
    def redirect_phone_number(message)
      target = SmsSafe.configuration.redirect_target
      case target
        when String then target
        when Proc   then target.call(message)
        else
          raise InvalidConfigSettingError.new("Ensure redirect_target is a String or a Proc. It was: #{SmsSafe.configuration.redirect_target.inspect}")
      end
    end

    # Modifies the text of the message to indicate it was redirected
    # Simply appends "(SmsSafe: original_recipient_number)", for brevity
    #
    # @param [Message] message the message we are redirecting
    # @return [String] the new text for the SMS
    def redirect_text(message)
      "#{message.text} (SmsSafe: #{message.to})"
    end

    # Sends an e-mail to the specified address, instead of
    # @return nil, to stop the sending
    def email(message)
      recipient = email_recipient(message)
      body = email_body(message)
      mail = Mail.new do
        from     recipient
        to       recipient
        subject  "SmsSafe: #{message.to} - #{message.text}"
        body     body
      end
      deliver_email(mail)

      nil # Must return nil to stop the sending
    end

    # Delivers the email through Mail, or ActionMailer, whatever is there
    # @param [Mail] mail to send
    # @return [Mail] the same mail received as parameter
    def deliver_email(mail)
      # Ugly hack, or beautiful elegance? No idea, really...
      # We don't want a dependency on ActionMailer, but we want our users that have ActionMailer configured
      #   to not need to configure Mail too, so we want to take the ActionMailer configuration magically
      #   if it's there
      if defined?(ActionMailer)
        ActionMailer::Base.wrap_delivery_behavior(mail)
      end

      mail.deliver!
    end

    # Decides which email address to send the SMS to
    # @param [Message] message the message we are emailing
    # @return [String] the email address to email it to
    def email_recipient(message)
      target = SmsSafe.configuration.email_target
      case target
        when String then target
        when Proc   then target.call(message)
        else
          raise InvalidConfigSettingError.new("Ensure email_target is a String or a Proc. It was: #{SmsSafe.configuration.email_target.inspect}")
      end
    end

    # Returns the Body for the e-mail that we'll send
    # @param [Message] message the message we are emailing
    # @return [String] the email body
    def email_body(message)
      <<-EOS
This email was originally an SMS that SmsSafe intercepted:

From: #{message.from}
To: #{message.to}
Text: #{message.text}

Full object: #{message.original_message.inspect}
      EOS
    end

    # Discards the message. Essentially doesn't do anything. Will sleep for a bit, however, if
    #   configuration.discard_delay is set.
    # @return nil, to stop the sending
    def discard
      # Delay to simulate the time it takes to talk to the external service
      if !SmsSafe.configuration.discard_delay.nil? && SmsSafe.configuration.discard_delay > 0
        delay = SmsSafe.configuration.discard_delay.to_f / 1000 # delay is specified in ms
        sleep delay
      end

      # Must return nil to stop the sending
      nil
    end

    # Converts an SMS message from whatever object the texter gem uses into our generic Message
    # Must be overridden by each gem's interceptor
    #
    # @param [Object] message that is being sent
    # @return [Message] the message converted into our own Message class
    def convert_message(message)
      raise "Must override!"
    end

    # Returns a modified version of the original message with new recipient and text,
    #   to give back to the texter gem to send.
    # Must be overridden by each gem's interceptor
    # Call redirect_phone_number and redirect_text to get the new recipient and text, and
    #  modify message.original_message
    #
    # @param [Message] message that is being sent, unmodified
    # @return [Object] modified message to send, of the type the texter gem uses
    def redirect(message)
      raise "Must override!"
    end
  end
end