require 'active_support/core_ext/numeric/time'
require 'spec_helper'
require 'spec_helpers/globalize_configurator'
require 'timecop'
require 'yaml'

include Txdb::Backends

describe Globalize::Writer, globalize_config: true do
  include_context :globalize

  describe '#write_content' do
    let(:base_resource) do
      # project_slug, resource_slug, type, source_locale, source_file,
      # lang_map, translation_file
      Txgh::TxResource.new(
        'project_slug', 'resource_slug', Globalize::Backend::RESOURCE_TYPE,
        'source_locale', 'source_file', nil, nil
      )
    end

    context 'with some content' do
      before(:each) do
        @sprocket_id = widgets.connection.insert(name: 'sprocket')

        sprocket_en_id = widget_translations.connection.insert(
          widget_id: @sprocket_id, name: 'sprocket', locale: 'en'
        )

        @writer = Globalize::Writer.new(widget_translations)

        @content = YAML.dump(
          'widget_translations' => {
            @sprocket_id => { name: 'sproqueta' }
          }
        )

        @resource = Txdb::TxResource.new(base_resource, @content)
      end

      it 'inserts the translations into the database' do
        expect { @writer.write_content(@resource, 'es') }.to(
          change { widget_translations.connection.count }.from(1).to(2)
        )

        translation = widget_translations.connection.order(:id).last

        expect(translation).to include(
          widget_id: @sprocket_id, name: 'sproqueta', locale: 'es'
        )
      end

      context 'with created_at and updated_at columns' do
        before(:each) do
          database.connection.alter_table(:widget_translations) do
            add_column :created_at, Time
            add_column :updated_at, Time
          end
        end

        it 'fills in the created_at and updated_at columns' do
          Timecop.freeze(Time.now) do
            @writer.write_content(@resource, 'es')
            translation = widget_translations.connection.order(:id).last
            expect(translation[:created_at].to_i).to eq(Time.now.utc.to_i)
            expect(translation[:updated_at].to_i).to eq(Time.now.utc.to_i)
          end
        end

        it 'updates the updated_at column if the record already exists' do
          @writer.write_content(@resource, 'es')

          today = Time.now + 1.day  # groundhog day

          Timecop.freeze(today) do
            translation = widget_translations.connection.first
            expect(translation[:updated_at].to_i).to_not eq(today.utc.to_i)

            # record already exists, so should get updated with new timestamp
            @writer.write_content(@resource, 'es')
            translation = widget_translations.connection.order(:id).last
            expect(translation[:updated_at].to_i).to eq(today.utc.to_i)
          end
        end
      end
    end

    it 'updates the record if it already exists' do
      sprocket_id = widgets.connection.insert(name: 'sprocket')

      sprocket_en_id = widget_translations.connection.insert(
        widget_id: sprocket_id, locale: 'en', name: 'sprocket'
      )

      sprocket_es_id = widget_translations.connection.insert(
        widget_id: sprocket_id, locale: 'es', name: 'sproqueta'
      )

      writer = Globalize::Writer.new(widget_translations)

      content = YAML.dump(
        'widget_translations' => {
          sprocket_id => { name: 'sproqueta2' }
        }
      )

      resource = Txdb::TxResource.new(base_resource, content)

      expect { writer.write_content(resource, 'es') }.to_not(
        change { widget_translations.connection.count }
      )

      translation = widget_translations.connection.where(id: sprocket_es_id).first
      expect(translation).to include(name: 'sproqueta2')
    end
  end
end
