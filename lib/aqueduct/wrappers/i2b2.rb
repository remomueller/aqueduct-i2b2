require 'aqueduct'

require 'net/http'
require 'net/https'
require 'uri'

require 'base64'
require 'openssl'

module Aqueduct
  module Wrappers
    class I2b2
      include Aqueduct::Wrapper

      DOMAIN = 'i2b2demo'

      def external_concepts(folder = '', search_term = '')
        search_term.blank? ? get_concepts(folder) : search_for_term(folder, search_term)
      end

      def external_concept_information(external_key = '')
        error = ''
        result = {}

        service_url = '/i2b2/rest/OntologyService/getTermInfo'

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns3:request", "xmlns:ns3" => "http://www.i2b2.org/xsd/hive/msg/1.1/",
                                "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/ont/1.1/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/plugin/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2 Ontology', 1.6, 'i2b2 Hive',
                                               'Ontology Cell', 1.6, 'i2b2 Hive')
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms 180000
          end
          req.message_body do |mgb|
            mgb.tag!('ns4:get_term_info', "blob" => "true", "type" => "core", "synonyms" => "true", "hiddens" => "true") do |gti|
              gti.tag!('self') do |sef|
                sef.text! external_key
              end
            end
          end
        end

        result_hash = process_concepts(send_message(xml.target!, service_url))
        result = result_hash[:result].first unless result_hash[:result].first.blank?
        { result: result, error: result_hash[:error] }
      end

      def count(query_concepts, conditions, tables, join_conditions, concept_to_count)
        get_total_count(query_concepts.find_all_by_id(eval(conditions)))
      end

      def use_sql?
        false
      end

      def concept_tables(query_concept)
        { result: [], error: '' }
      end

      def conditions(query_concepts)
        { conditions: "#{query_concepts.collect{|qc| qc.id}}", error: '' }
      end

      def query(sql_statement)
        # result = [[['cname', 'cname2', 'cname3', 'cname4'],[1,2,3,4],[5,nil,7,8]],2]
        result = [[]]

        concept_list = []
        # TODO: Replace this with query_concepts (pass in query concepts initially?)

        query_concepts = QueryConcept.find_all_by_id(eval(sql_statement))


        result_hash = get_all_covariates(query_concepts)

        result = result_hash[:result]
        error = result_hash[:error]

        # THIS WORKS! (For limited ors and non complex things)
        # query_concepts.each_with_index do |query_concept, index|
        #   concept_list << { key: query_concept.external_key, right_operator: query_concept.right_operator, negated: query_concept.negated }
        # end
        #
        # conditions = query_definition(concept_list)
        #
        # patient_data = run_query_get_patient_data(conditions)
        #
        # if patient_data.first and patient_data.first[1]
        #   all_concepts = patient_data.first[1].keys
        #   result[0] = ['patient_id'] + all_concepts
        # end
        #
        # patient_data.each_pair do |patient_id, value_hash|
        #   row_data = [patient_id]
        #   all_concepts.each do |concept|
        #     row_data << value_hash[concept][:value]
        #   end
        #   result << row_data
        # end

        [result, result.size]
      end

      # TODO: Update i2b2 connect to make sure the server is up and running
      def connect
        true
      end

      private

      def current_time
        @current_time ||= Time.now.strftime("%Y-%m-%dT%T") + Time.now.strftime("%z").gsub(/([+-]?\d\d)(\d\d)/, "#{$1}:#{$2}")
      end

      def message_header(redirect_url, sending_app_name, sending_app_version, sending_facility_name, receiving_app_name, receiving_app_version, receiving_facility_name, aat = 'AL', token_available = true)
        @message_header ||= begin
          xml = ::Builder::XmlMarkup.new
          xml.proxy do |pxy|
            pxy.redirect_url                    "#{@source.host}#{redirect_url}"
          end
          xml.sending_application do |sap|
            sap.application_name                sending_app_name
            sap.application_version             sending_app_version
          end
          xml.sending_facility do |sfa|
            sfa.facility_name                   sending_facility_name
          end
          xml.i2b2_version_compatible           1.1
          xml.hl7_version_compatible            2.4
          xml.datetime_of_message               current_time
          xml.message_control_id do |mci|
            mci.message_num                     'iFL7f7DmuTj349bdHcDCl'
            mci.instance_num                    0
          end
          xml.processing_id do |pi|
            pi.processing_id                    'P'
            pi.processing_mode                  'I'
          end
          xml.accept_acknowledgement_type       aat
          xml.application_acknowledgement_type  'AL'
          xml.country_code                      'US'
          xml.project_id                        'Demo'
          xml.receiving_application do |rap|
            rap.application_name                receiving_app_name
            rap.application_version             receiving_app_version
          end
          xml.receiving_facility do |rfa|
            rfa.facility_name                   receiving_facility_name
          end
          xml.security do |sec|
            sec.domain                          DOMAIN
            sec.username                        @source.username
            if token_available
              sec.tag!('password', 'token_ms_timeout' => '1800000', 'is_token' => 'true') do |p|
                p.text!                         session_key.to_s
              end
            else
              sec.password                      @source.password
            end
          end
          xml.target!
        end
      end

      def session_key
        @session_key ||= begin
          service_url = '/i2b2/rest/PMService/getServices'

          xml = ::Builder::XmlMarkup.new
          xml.instruct! :xml, standalone: 'yes'
          xml.tag!("i2b2:request", "xmlns:i2b2" => "http://www.i2b2.org/xsd/hive/msg/1.1/", "xmlns:pm" => "http://www.i2b2.org/xsd/cell/pm/1.1/") do |req|
            req.message_header do |mhr|
              mhr << message_header('', 'i2b2 Project Management', 1.6, 'i2b2 Hive',
                                        'Project Management Cell', 1.6, 'i2b2 Hive', 'AL', false)
            end
            req.request_header do |rqh|
              rqh.result_waittime_ms 180000
            end
            req.message_body do |mgb|
              mgb.tag!('pm:get_user_configuration') do |cfg|
                cfg.project 'undefined'
              end
            end
          end

          result_hash = send_message(xml.target!, service_url)

          if result_hash[:error].blank?
            # Pull out service key
            key = result_hash[:result].scan(/<password .*?>(.*)<\/password>/).first.first
          else
            Rails.logger.debug "Error: #{result_hash[:error]}"
            nil
          end
        end
      end

      def xmlitem(xml_string, xml_element)
        xml_string.scan(/<#{xml_element}>(.*?)<\/#{xml_element}>/m).flatten.first.to_s
      end

      def process_concepts(result_hash, queryable = true)
        categories = []

        if result_hash[:error].blank?
          concepts = result_hash[:result].scan(/<concept>(.*?)<\/concept>/m)
          concepts.flatten.each do |c|
            visual_attributes = xmlitem(c, 'visualattributes')

            is_folder = ['CA', 'FA'].include?(visual_attributes[0..1])

            full_folder = xmlitem(c, 'key')

            categories << { tooltip:            xmlitem(c, 'tooltip'),
                            is_folder:          is_folder,
                            is_queryable:       queryable,
                            key:                xmlitem(c, 'key'),
                            level:              xmlitem(c, 'level'),
                            name:               xmlitem(c, 'name'),
                            visual_attributes:  visual_attributes,
                            totalnum:           xmlitem(c, 'totalnum'),
                            source_id:          @source.id,
                            folder:             @source.name }
            # c.first.gsub(/[^\w<>]/, '').inspect  # gsub(" ", "_")
          end
        end

        { result: categories, error: result_hash[:error] }
      end

      def get_categories
        service_url = '/i2b2/rest/OntologyService/getCategories'

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns3:request", "xmlns:ns3" => "http://www.i2b2.org/xsd/hive/msg/1.1/",
                                "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/ont/1.1/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/plugin/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2 Project Management', 1.6, 'i2b2 Hive',
                                               'Project Management Cell', 1.6, 'i2b2 Hive')
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms 180000
          end
          req.message_body do |mgb|
            mgb.tag!('ns4:get_categories', "type" => "core")
          end
        end

        process_concepts send_message(xml.target!, service_url), false
      end

      def get_child_concepts(folder = '')
        service_url = '/i2b2/rest/OntologyService/getChildren'

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns3:request", "xmlns:ns3" => "http://www.i2b2.org/xsd/hive/msg/1.1/",
                                "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/ont/1.1/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/plugin/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2 Ontology', 1.6, 'i2b2 Hive',
                                               'Ontology Cell', 1.6, 'i2b2 Hive')
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms 180000
          end
          req.message_body do |mgb|
            mgb.tag!('ns4:get_children', "blob" => "false", "type" => "core", "max" => "500", "synonyms" => "false", "hiddens" => "false") do |chi|
              chi.parent folder
            end
          end
        end

        process_concepts send_message(xml.target!, service_url)
      end

      def get_concepts(folder = '')
        folder.blank? ? get_categories : get_child_concepts(folder)
      end

      def items(concept_list)
        result = ''

        concept_list.each do |concept_hash|
          item = ''
          item << "\n\n<item>"
          item << "\n  <hlevel>#{concept_hash[:level]}</hlevel>"
          item << "\n  <item_name>#{concept_hash[:name]}</item_name>"
          item << "\n  <item_key>#{concept_hash[:key]}</item_key>"
          item << "\n  <tooltip>#{concept_hash[:tooltip]}</tooltip>"
          item << "\n  <class>ENC</class>"
          item << "\n  <item_icon>#{concept_hash[:visual_attributes]}</item_icon>"
          item << "\n  <item_is_synonym>false</item_is_synonym>"
          item << "\n</item>\n\n"
          result << item
        end

        result
      end

      def query_definition(concept_list, query_name = Time.now.to_s)
        panel_number = 0
        new_panel = true

        query_name = query_name.gsub(/[^\w \:+-]/, '-')

        q = "<query_definition>"
        q << "<query_name>#{query_name}</query_name>"
        q << "<query_timing>ANY</query_timing>"
        q << "<specificity_scale>0</specificity_scale>"

        concept_list.each do |concept_item|
          if new_panel
            panel_number += 1
            q += "#{'</panel>' unless panel_number == 1}<panel><panel_number>#{panel_number}</panel_number><panel_accuracy_scale>0</panel_accuracy_scale><invert>#{concept_item[:negated] ? '1' : '0'}</invert><panel_timing>ANY</panel_timing><total_item_occurrences>1</total_item_occurrences>"
          end
          q += items([concept_item])
          new_panel = (concept_item[:right_operator] == 'and')
        end

        q << "</panel></query_definition>"
        q
      end

      # This function may be necessary in certain cases (faster count for single concepts)
      # Currently it's not called, as of initial version 2.9.0
      def run_query_get_count(conditions)
        result = 0
        query_master_id = '0'

        service_url = "/i2b2/rest/QueryToolService/request"

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns6:request", "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/crc/psm/1.1/",
                                "xmlns:ns7" => "http://www.i2b2.org/xsd/cell/ont/1.1/",
                                "xmlns:ns3" => "http://www.i2b2.org/xsd/cell/crc/pdo/1.1/",
                                "xmlns:ns5" => "http://www.i2b2.org/xsd/hive/plugin/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/pdo/1.1/",
                                "xmlns:ns6" => "http://www.i2b2.org/xsd/hive/msg/1.1/",
                                "xmlns:ns8" => "http://www.i2b2.org/xsd/cell/crc/psm/querydefinition/1.1/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2_QueryTool', 1.6, 'PHS',
                                               'i2b2_DataRepositoryCell', 1.6, 'PHS', 'messageId')

            # Message Type doesn't look like it is required...what's the purpose?
            mhr.message_type do |mtp|
              mtp.message_code            'Q04'
              mtp.event_type              'EQQ'
            end
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms        180000
          end
          req.message_body do |mgb|
            mgb.tag!('ns4:psmheader') do |pmh|
              pmh.user('group' => 'Demo', "login" => "demo") do |usr|
                usr.text!                 'demo'
              end
              pmh.patient_set_limit       0
              pmh.estimated_time          0
              pmh.query_mode              'optimize_without_temp_table'
              pmh.request_type            'CRC_QRY_runQueryInstance_fromQueryDefinition'
            end
            mgb.tag!('ns4:request', "xsi:type" => "ns4:query_definition_requestType", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance") do |req|
              req << conditions
              req.result_output_list do |rol|
                rol.result_output("priority_index" => "9", "name" => "patient_count_xml") # The only difference between this and run_query_get_patient_set
              end
            end
          end
        end

        result_hash = send_message(xml.target!, service_url)

        result = xmlitem(result_hash[:result], 'set_size') if result_hash[:error].blank?
        query_master_id = xmlitem(result_hash[:result], 'result_instance_id') if result_hash[:error].blank?

        {result: result, error: result_hash[:error], query_master_id: query_master_id}
      end

      def run_query_get_patient_set(conditions)
        result = 0
        service_url = "/i2b2/rest/QueryToolService/request"

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns6:request", "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/crc/psm/1.1/",
                                "xmlns:ns7" => "http://www.i2b2.org/xsd/cell/ont/1.1/",
                                "xmlns:ns3" => "http://www.i2b2.org/xsd/cell/crc/pdo/1.1/",
                                "xmlns:ns5" => "http://www.i2b2.org/xsd/hive/plugin/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/pdo/1.1/",
                                "xmlns:ns6" => "http://www.i2b2.org/xsd/hive/msg/1.1/",
                                "xmlns:ns8" => "http://www.i2b2.org/xsd/cell/crc/psm/querydefinition/1.1/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2_QueryTool', 1.6, 'PHS',
                                               'i2b2_DataRepositoryCell', 1.6, 'PHS', 'messageId')

            # Message Type doesn't look like it is required...what's the purpose?
            mhr.message_type do |mtp|
              mtp.message_code            'Q04'
              mtp.event_type              'EQQ'
            end
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms        180000
          end
          req.message_body do |mgb|
            mgb.tag!('ns4:psmheader') do |pmh|
              pmh.user('group' => 'Demo', "login" => "demo") do |usr|
                usr.text!                 'demo'
              end
              pmh.patient_set_limit       0
              pmh.estimated_time          0
              pmh.query_mode              'optimize_without_temp_table'
              pmh.request_type            'CRC_QRY_runQueryInstance_fromQueryDefinition'
            end
            mgb.tag!('ns4:request', "xsi:type" => "ns4:query_definition_requestType", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance") do |req|
              req << conditions
              req.result_output_list do |rol|
                rol.result_output("priority_index" => "9", "name" => "patientset")
              end
            end
          end
        end

        result_hash = send_message(xml.target!, service_url)

        result = xmlitem(result_hash[:result], 'set_size') if result_hash[:error].blank?
        query_master_id = xmlitem(result_hash[:result], 'result_instance_id') if result_hash[:error].blank?


        { result: result, error: result_hash[:error], query_master_id: query_master_id }
      end

      def run_pdo_request(conditions)

        result_hash = run_query_get_patient_set(conditions)
        if result_hash[:error].blank?
          query_master_id = result_hash[:query_master_id]
        else

        end

        service_url = "/i2b2/rest/QueryToolService/pdorequest"

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns6:request", "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/crc/psm/1.1/",
                                "xmlns:ns7" => "http://www.i2b2.org/xsd/cell/crc/psm/querydefinition/1.1/",
                                "xmlns:ns3" => "http://www.i2b2.org/xsd/cell/crc/pdo/1.1/",
                                "xmlns:ns5" => "http://www.i2b2.org/xsd/hive/plugin/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/pdo/1.1/",
                                "xmlns:ns6" => "http://www.i2b2.org/xsd/hive/msg/1.1/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2_QueryTool', 1.6, 'PHS',
                                               'i2b2_DataRepositoryCell', 1.6, 'PHS', 'messageId')
            # Message Type doesn't look like it is required...what's the purpose?
            mhr.message_type do |mtp|
              mtp.message_code            'Q04'
              mtp.event_type              'EQQ'
            end
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms        180000
          end
          req.message_body do |mgb|

            mgb.tag!('ns3:pdoheader') do |pdh|
              pdh.patient_set_limit 0
              pdh.estimated_time 180000
              pdh.request_type 'getPDO_fromInputList'
            end

            mgb.tag!('ns3:request', "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance", "xsi:type" => "ns3:GetPDOFromInputList_requestType") do |req|
              req.input_list do |ipl|
                ipl.tag!('patient_list', "max" => "1000000", "min" => "0") do |pal|
                  pal.patient_set_coll_id query_master_id
                end
              end
              req.filter_list
              req.output_option do |opo|
                opo.tag!('patient_set', "select" => "using_input_list", "onlykeys" => "false")
              end
            end
          end
        end

        result_hash = send_message(xml.target!, service_url)
        result_hash
      end

      def run_query_get_patient_ids(conditions)

        result_hash = run_pdo_request(conditions)

        patient_ids = []

        if result_hash[:error].blank?
          patient_ids = result_hash[:result].scan(/<patient_id>(.*?)<\/patient_id>/).flatten
        else
          Rails.logger.debug result_hash[:error]
        end

        { result: patient_ids, error: result_hash[:error] }
      end

      def run_query_get_patient_data(conditions)
        result_hash = run_pdo_request(conditions)
        patient_data = {}

        if result_hash[:error].blank?
          # TODO: Handle case or result_hash being nil...perhaps with a to_s
          id = result_hash[:result].scan(/<ns2:patient_set>(.*?)<\/ns2:patient_set>/m).flatten.first
          id.scan(/<patient>(.*?)<\/patient>/m).each do |c|
            patient_id = c.to_s.scan(/<patient_id>(.*?)<\/patient_id>/m).flatten.first

            patient_data[patient_id] = {}



            test2 = c.to_s.scan(/(<param .*?(<\/param>|\/>))/m).each do |pars|
              p_string = pars.flatten.first
              value = nil
              unless pars[1] == "/>"
                value = p_string.scan(/<param .*?>(.*?)<\/param>/m).flatten.first
              end
              column_name = p_string.scan(/column=\\"(.*?)\\"/m).flatten.first
              display_name = p_string.scan(/column\_descriptor=\\"(.*?)\\"/m).flatten.first || column_name.to_s.capitalize #.titleize
              patient_data[patient_id][column_name] = { value: value, display_name: display_name }
            end
          end
        else
          # TODO: Push error out to upper service
          puts result_hash[:error]
        end

        patient_data
      end

      def get_total_count(query_concepts)
        error = ''
        eval_string = ''
        patient_ids = [] # This one returns the combined evaluated expressions
        all_patient_ids = [] # this is a partial patient ids...
        query_concepts.each_with_index do |query_concept, index|
          result = query_definition([{key: query_concept.external_key, right_operator: query_concept.right_operator, negated: query_concept.negated}]) # , query_concept.query.name
          result_hash = run_query_get_patient_ids(result)
          all_patient_ids << result_hash[:result]
          error = result_hash[:error] unless result_hash[:error].blank?

          eval_string << "("*query_concept.left_brackets unless query_concepts.size == 1
          eval_string << result_hash[:result].to_s
          eval_string << ")"*query_concept.right_brackets unless query_concepts.size == 1
          if index < query_concepts.size - 1
            case query_concept.right_operator when 'and'
              eval_string << '&'
            when 'or'
              eval_string << '|'
            else
              return { result: 0, error: "Invalid operator '#{query_concept.right_operator}' in evaluation string.", sql_conditions: eval_string }
            end
          end
        end

        total_count = 0
        begin
          total_count = eval(eval_string).size
          patient_ids = eval(eval_string)
        rescue => e
          error = "#{e}"
        end

        { result: total_count, error: error, sql_conditions: eval_string, patient_ids: patient_ids }
      end

      def get_total_query_patient_ids(query_concepts)
        result = []
        result_hash = get_total_count(query_concepts)
        result = result_hash[:patient_ids] if result_hash[:error].blank?
        result
      end

      # Access each query_concept individually and retrieve all the associated data, then trim the data based on the actual resulting patient IDs from the query.
      def get_all_covariates(query_concepts)
        error = ''
        result = [[]]
        all_patient_ids = []
        all_concepts = []


        query_concepts.each_with_index do |query_concept, index|
          conditions = query_definition([{ key: query_concept.external_key, right_operator: query_concept.right_operator, negated: query_concept.negated }])
          patient_data = run_query_get_patient_data(conditions)

          if patient_data.first and patient_data.first[1] and result[0].blank?
            all_concepts = patient_data.first[1].keys
            result[0] = ['patient_id'] + all_concepts
          end

          patient_data.each_pair do |patient_id, value_hash|
            row_data = [patient_id]

            all_concepts.each do |concept|
              row_data << value_hash[concept][:value]
            end
            result << row_data
          end
        end

        all_patient_ids = get_total_query_patient_ids(query_concepts)
        overall_result = [[]]

        overall_result[0] = result[0]

        result[1..-1].each do |row|
          if all_patient_ids.include?(row[0])
            overall_result << row
            all_patient_ids.delete(row[0])
          end
        end

        { result: overall_result, error: error }
      end

      def search_for_term(folder, term)
        categories_hash = get_categories

        return categories_hash unless categories_hash[:error].blank?

        concepts = []
        error = ''

        categories = categories_hash[:result].collect{|c| c[:key].gsub(/\\\\/, '').split(/\\/).first.to_s}

        categories.each do |category|
          result_hash = search_for_term_helper(term, category)
          concepts = (concepts | result_hash[:result]) if result_hash[:error].blank?
          error = result_hash[:error] unless result_hash[:error].blank?
        end

        concepts = concepts.select{|c| (c[:folder] == folder or folder.blank?)}.uniq

        { result: concepts, error: error }
      end

      def search_for_term_helper(term, category)

        service_url = '/i2b2/rest/OntologyService/getNameInfo'

        xml = ::Builder::XmlMarkup.new
        xml.instruct! :xml, standalone: 'yes'
        xml.tag!("ns3:request", "xmlns:ns3" => "http://www.i2b2.org/xsd/hive/msg/1.1/",
                                "xmlns:ns4" => "http://www.i2b2.org/xsd/cell/ont/1.1/",
                                "xmlns:ns2" => "http://www.i2b2.org/xsd/hive/plugin/") do |req|
          req.message_header do |mhr|
            mhr << message_header(service_url, 'i2b2 Ontology', 1.6, 'i2b2 Hive',
                                               'Ontology Cell', 1.6, 'i2b2 Hive')
          end
          req.request_header do |rqh|
            rqh.result_waittime_ms 180000
          end
          req.message_body do |mgb|
            mgb.tag!('ns4:get_name_info', "blob" => "true", "type" => "core", "max" => "500", "category" => category) do |gni|
              gni.tag!('match_str', "strategy" => "left") do |mst|
                mst.text! term
              end
            end
          end
        end

        process_concepts send_message(xml.target!, service_url)
      end

      def send_message(message, service)

        url = URI.parse(@source.host + service)

        use_secure = (url.scheme == 'https')

        https = Net::HTTP.new(url.host, url.port)
        https.open_timeout = 10 # Seconds
        https.read_timeout = 30 # might need to be longer?
        if use_secure
          https.use_ssl = true
          https.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        headers = {'Content-Type' => 'text/xml'};
        data = ''
        error = ''
        begin
          response = https.post2(url.path, message, headers)
          data = response.body

          case response.class.name
          when 'Net::HTTPOK'
          else
            error = "Error: #{response.class.name} #{data}"
          end
        rescue Exception => e
          error = "Exception: #{e} #{response.class.name} #{data}"
        end

        return { result: data, error: error }
      end
    end
  end
end