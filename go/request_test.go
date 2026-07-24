package clientsignals

import (
	"net/http"
	"testing"
)

type requestClassificationFixture struct {
	Name    string            `json:"name"`
	Headers map[string]string `json:"headers"`
	Want    struct {
		Operator string `json:"operator"`
		Agent    string `json:"agent"`
	} `json:"want"`
}

type apiRouteFixture struct {
	Name          string   `json:"name"`
	Method        string   `json:"method"`
	RouteTemplate string   `json:"routeTemplate"`
	RequestPath   string   `json:"requestPath"`
	Prefixes      []string `json:"prefixes"`
	WantRoute     string   `json:"wantRoute"`
	Tracked       bool     `json:"tracked"`
}

func TestClassifyRequestHeaders_SharedFixtures(t *testing.T) {
	t.Parallel()

	var fixtures []requestClassificationFixture
	readSpecFixture(t, "request-classification-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		fixture := fixture
		t.Run(fixture.Name, func(t *testing.T) {
			t.Parallel()

			header := make(http.Header, len(fixture.Headers))
			for name, value := range fixture.Headers {
				header.Set(name, value)
			}

			want := RequestClassification{
				Operator: fixture.Want.Operator,
				Agent:    fixture.Want.Agent,
			}
			if got := ClassifyRequestHeaders(header); got != want {
				t.Fatalf("ClassifyRequestHeaders() = %#v, want %#v", got, want)
			}
		})
	}
}

func TestTrackedAPIRoute_SharedFixtures(t *testing.T) {
	t.Parallel()

	var fixtures []apiRouteFixture
	readSpecFixture(t, "api-route-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		fixture := fixture
		t.Run(fixture.Name, func(t *testing.T) {
			t.Parallel()

			got, tracked := TrackedAPIRoute(
				fixture.Method,
				fixture.RouteTemplate,
				fixture.RequestPath,
				fixture.Prefixes,
			)
			if got != fixture.WantRoute || tracked != fixture.Tracked {
				t.Fatalf(
					"TrackedAPIRoute() = (%q, %t), want (%q, %t)",
					got,
					tracked,
					fixture.WantRoute,
					fixture.Tracked,
				)
			}
		})
	}
}
