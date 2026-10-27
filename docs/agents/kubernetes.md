# Kubernetes and Flux schemas

Before you write or edit a Kubernetes, Flux, Gateway API or other CRD manifest, look up the real kind and fields on the `flux-schema-catalog` MCP server (`mcp__flux-schema-catalog__*`). Use `grep_catalog` to find the apiVersion and kind, `grep_schema` for field names, types and required values, and `get_schema` only when you need the full schema. Do not write fields from memory. If the server is not available, say so before you edit.
