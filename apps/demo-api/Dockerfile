FROM golang:1.27.0-alpine AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download

COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/demo-api .

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/demo-api /demo-api

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/demo-api"]
