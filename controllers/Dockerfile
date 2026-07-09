# Multi-stage build: compile a static Go binary, then run it from a minimal
# distroless base with no shell — keeps the attack surface small for a
# cluster-privileged controller.
FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod ./
# go.sum is intentionally not committed to this scaffold (no network access
# to the Go module proxy in the environment that generated it); run
# `go mod tidy` once against a real proxy before building in CI.
RUN go mod download || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/selfhealing-operator .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/selfhealing-operator /selfhealing-operator
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/selfhealing-operator"]
