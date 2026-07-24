package clientsignals

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
)

const (
	// RequestMetricName is the canonical Prometheus counter name for requests
	// classified using client signals.
	RequestMetricName = "fly_client_signals_requests_total"

	requestMetricHelp = "Requests classified by coarse client signals"
)

// RequestCounter is the canonical Prometheus collector for requests classified
// using client signals. It is safe for concurrent use.
type RequestCounter struct {
	service              string
	trackedRoutePrefixes []string
	counter              *prometheus.CounterVec
}

// NewRequestCounter constructs the canonical client-signals request collector.
// The caller is responsible for registering it with a Prometheus registerer.
func NewRequestCounter(service string, trackedRoutePrefixes []string) *RequestCounter {
	return &RequestCounter{
		service:              service,
		trackedRoutePrefixes: append([]string(nil), trackedRoutePrefixes...),
		counter: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: RequestMetricName,
				Help: requestMetricHelp,
			},
			[]string{"service", "route", "operator", "agent"},
		),
	}
}

// Observe records req when its matched route template or raw request path
// belongs to a configured prefix. routeTemplate should be the bounded template
// reported by the service's router, not the raw request path.
func (c *RequestCounter) Observe(req *http.Request, routeTemplate string) bool {
	route, tracked := TrackedRoute(
		req.Method,
		routeTemplate,
		req.URL.Path,
		c.trackedRoutePrefixes,
	)
	if !tracked {
		return false
	}

	classification := ClassifyRequestHeaders(req.Header)
	c.counter.WithLabelValues(
		c.service,
		route,
		classification.Operator,
		classification.Agent,
	).Inc()

	return true
}

// Describe implements prometheus.Collector.
func (c *RequestCounter) Describe(ch chan<- *prometheus.Desc) {
	c.counter.Describe(ch)
}

// Collect implements prometheus.Collector.
func (c *RequestCounter) Collect(ch chan<- prometheus.Metric) {
	c.counter.Collect(ch)
}
