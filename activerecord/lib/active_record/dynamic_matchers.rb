module ActiveRecord
  module DynamicMatchers
    def respond_to?(method_id, include_private = false)
      match       = find_dynamic_match(method_id)
      valid_match = match && all_attributes_exists?(match.attribute_names)

      valid_match || super
    end

    private

    # Enables dynamic finders like <tt>User.find_by_user_name(user_name)</tt> and
    # <tt>User.scoped_by_user_name(user_name). Refer to Dynamic attribute-based finders
    # section at the top of this file for more detailed information.
    #
    # It's even possible to use all the additional parameters to +find+. For example, the
    # full interface for +find_all_by_amount+ is actually <tt>find_all_by_amount(amount, options)</tt>.
    #
    # Each dynamic finder using <tt>scoped_by_*</tt> is also defined in the class after it
    # is first invoked, so that future attempts to use it do not run through method_missing.
    def method_missing(method_id, *arguments, &block)
      if match = find_dynamic_match(method_id)
        attribute_names = match.attribute_names
        super unless all_attributes_exists?(attribute_names)

        unless match.valid_arguments?(arguments)
          method_trace = "#{__FILE__}:#{__LINE__}:in `#{method_id}'"
          backtrace = [method_trace] + caller
          raise ArgumentError, "wrong number of arguments (#{arguments.size} for #{attribute_names.size})", backtrace
        end

        if match.respond_to?(:scope?) && match.scope?
          define_scope_method(method_id, attribute_names)
          send(method_id, *arguments)
        elsif match.finder?
          options = arguments.extract_options!
          relation = options.any? ? scoped(options) : scoped
          relation.send :find_by_attributes, match, attribute_names, *arguments, &block
        elsif match.instantiator?
          scoped.send :find_or_instantiator_by_attributes, match, attribute_names, *arguments, &block
        end
      else
        super
      end
    end

    def define_scope_method(method_id, attribute_names) #:nodoc
      self.class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def self.#{method_id}(*args)                                    # def self.scoped_by_user_name_and_password(*args)
          conditions = Hash[[:#{attribute_names.join(',:')}].zip(args)] #   conditions = Hash[[:user_name, :password].zip(args)]
          where(conditions)                                             #   where(conditions)
        end                                                             # end
      METHOD
    end

    def find_dynamic_match(method_id) #:nodoc:
      DynamicFinderMatch.match(method_id) || DynamicScopeMatch.match(method_id)
    end

    # Similar in purpose to +expand_hash_conditions_for_aggregates+.
    def expand_attribute_names_for_aggregates(attribute_names)
      attribute_names.map do |attribute_name|
        if aggregation = reflect_on_aggregation(attribute_name.to_sym)
          aggregate_mapping(aggregation).map do |field_attr, _|
            field_attr.to_sym
          end
        else
          attribute_name.to_sym
        end
      end.flatten
    end

    def all_attributes_exists?(attribute_names)
      (expand_attribute_names_for_aggregates(attribute_names) -
       column_methods_hash.keys).empty?
    end

    def aggregate_mapping(reflection)
      mapping = reflection.options[:mapping] || [reflection.name, reflection.name]
      mapping.first.is_a?(Array) ? mapping : [mapping]
    end
  end
end
