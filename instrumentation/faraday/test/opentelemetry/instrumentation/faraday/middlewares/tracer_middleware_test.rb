# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

# require Instrumentation so .install method is found:
require_relative '../../../../../lib/opentelemetry/instrumentation/faraday'
require_relative '../../../../../lib/opentelemetry/instrumentation/faraday/middlewares/tracer_middleware'

describe OpenTelemetry::Instrumentation::Faraday::Middlewares::TracerMiddleware do
  let(:instrumentation) { OpenTelemetry::Instrumentation::Faraday::Instrumentation.instance }
  let(:exporter) { EXPORTER }
  let(:span) { exporter.finished_spans.first }

  let(:client) do
    ::Faraday.new('http://example.com') do |builder|
      builder.adapter(:test) do |stub|
        stub.get('/success') { |_| [200, {}, 'OK'] }
        stub.get('/failure') { |_| [500, {}, 'OK'] }
        stub.get('/not_found') { |_| [404, {}, 'OK'] }
      end
    end
  end

  before do
    exporter.reset

    # this is currently a noop but this will future proof the test
    @orig_propagator = OpenTelemetry.propagation.http
    propagator = OpenTelemetry::Context::Propagation::Propagator.new(
      OpenTelemetry::Trace::Propagation::TraceContext.text_map_injector,
      OpenTelemetry::Trace::Propagation::TraceContext.text_map_extractor
    )
    OpenTelemetry.propagation.http = propagator
  end

  after do
    OpenTelemetry.propagation.http = @orig_propagator
  end

  describe 'first span' do
    before do
      instrumentation.install
    end

    it 'has http 200 attributes' do
      response = client.get('/success')

      _(span.name).must_equal 'HTTP GET'
      _(span.attributes['http.method']).must_equal 'GET'
      _(span.attributes['http.status_code']).must_equal 200
      _(span.attributes['http.url']).must_equal 'http://example.com/success'
      _(response.env.request_headers['Traceparent']).must_equal(
        "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      )
      _(span.attributes['code.lineno']).must_equal 50
      _(span.attributes['code.absolute_path']).must_equal __FILE__
    end

    it 'has http.status_code 404' do
      response = client.get('/not_found')

      _(span.name).must_equal 'HTTP GET'
      _(span.attributes['http.method']).must_equal 'GET'
      _(span.attributes['http.status_code']).must_equal 404
      _(span.attributes['http.url']).must_equal 'http://example.com/not_found'
      _(response.env.request_headers['Traceparent']).must_equal(
        "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      )
      _(span.attributes['code.lineno']).must_equal 64
      _(span.attributes['code.absolute_path']).must_equal __FILE__
    end

    it 'has http.status_code 500' do
      response = client.get('/failure')

      _(span.name).must_equal 'HTTP GET'
      _(span.attributes['http.method']).must_equal 'GET'
      _(span.attributes['http.status_code']).must_equal 500
      _(span.attributes['http.url']).must_equal 'http://example.com/failure'
      _(response.env.request_headers['Traceparent']).must_equal(
        "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      )
      _(span.attributes['code.lineno']).must_equal 78
      _(span.attributes['code.absolute_path']).must_equal __FILE__
    end
  end
end
