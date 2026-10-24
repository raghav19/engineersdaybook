# Kubernetes and Flux schemas

Before you write or edit a Kubernetes, Flux, Gateway API or other CRD manifest, look up the real kind and fields on the gateway's flux-schema-catalog (`mcp__mcp-gateway__*`). Use `grep_catalog` to find the apiVersion and kind, `grep_schema` for field names, types and required values, and `get_schema` only when you need the full schema. Do not write fields from memory. If the gateway is not available, say so before you edit.
