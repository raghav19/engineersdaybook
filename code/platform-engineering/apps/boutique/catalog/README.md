# Catalog of Online Boutique

This folder holds the files that describe Online Boutique for Backstage. The app team owns them. Backstage reads them from the branch `main`.

![Catalog structure of Online Boutique in Backstage: the Group and the User in org.yaml, and the System, the Components and the Resource in catalog-info.yaml](../../../docs/diagrams/catalog-structure.svg)

## The two files

| File | Entities | Content |
|---|---|---|
| `org.yaml` | 1 Group, 1 User | The team `boutique-team` and the user `raghav19`. The user is a member of the team. |
| `catalog-info.yaml` | 1 System, 11 Components, 1 Resource | The system `online-boutique`, its 11 services, and the cache `redis-cart`. |

Backstage has one catalog. The two files are two sources for that one catalog. Each entity links to the others by name, so the files can stay apart.

## How the fields connect the entities

Each link starts as a field in the `spec` of one entity. Backstage turns the field into a relation. It also adds the reverse relation on the other entity.

| Field in the YAML | Where we use it | Relation (and reverse) | Meaning |
|---|---|---|---|
| `spec.memberOf` | `User raghav19` | `memberOf` (`hasMember`) | The user is a member of the group. |
| `spec.owner` | System, 11 Components, Resource | `ownedBy` (`ownerOf`) | One group is the owner. |
| `spec.system` | 11 Components, Resource | `partOf` (`hasPart`) | The entity is a part of the system. |
| `spec.dependsOn` | 5 Components | `dependsOn` (`dependencyOf`) | The component needs the other component or resource to work. |
| `spec.children` | `Group boutique-team` | `parentOf` (`childOf`) | Child groups. The list is empty. It does not list users. |

An entity reference has the form `[kind:][namespace/]name`. For example, `group:default/boutique-team`. You can leave out the kind or the namespace when the context gives a default. The default namespace is `default`.

## Your understanding, checked against the Backstage docs

| What you said | Verdict | What the docs say |
|---|---|---|
| `org.yaml` is a catalog of orgs. | Not exact | The descriptor format documents these kinds: Component, Template, API, Group, User, Resource, System, Domain, Location. It has no kind `Organization`. The file name is our choice. The entities in the file are of the kinds `Group` and `User`. The docs call them the "Organizational Entities". |
| It is a single org that Backstage manages. | Not exact | Backstage does not manage the entities. The YAML files are the source of truth, and Backstage reads them. The docs say the files are "maintained by the respective owners". |
| The group holds a set of users. | Right | A group is "a team, a business unit, or a loose collection of people". You write the membership on the user (`spec.memberOf`, required). The group field `spec.children` lists child groups, not users. |
| The Boutique has another catalog. | Not exact | There is one catalog. `catalog-info.yaml` is one more file that feeds it. The entities link by reference across files. |
| Components map to services. | Partly right | A component is "a piece of software", here of the type `service`. It is not the Kubernetes Service. The annotation `backstage.io/kubernetes-label-selector` links it to the pods. |
| The System is the overarching app. | Right | A system is "a collection of resources and components that exposes one or several public APIs". Our system has no `API` entities yet. |
| The Resource is a dependency. | Right | A resource is the infrastructure "a component needs to operate at runtime". `cartservice` has `dependsOn: resource:default/redis-cart`. |
| Components have metadata with the group and the user they belong to. | Fix | The owner is `spec.owner`, not metadata. A component has one owner. The owner is a group (the default) or a user. Our files name the group only. The user connects to the components through the membership. |
| Ownership and dependency are one mapping. | Fix | They are two fields with two meanings: `spec.owner` and `spec.dependsOn`. |

The docs also say what ownership is for. The owner is the "point of contact if something goes wrong". The docs say ownership is for display. It is "not to be used by automated processes to for example assign authorization in runtime systems".

## What I did not check

- How the Backstage UI finds "my components" for a signed-in user. I expect it uses the group membership of the user. The docs I read do not say so.
- The `API` kind. Our catalog has no `API` entity. The Boutique services talk over gRPC. A later step can add one `API` entity for each `.proto` file.

## Sources

I read these pages from the Backstage repo (`backstage/backstage`, commit `bc53efe`, folder `docs/features/software-catalog`):

- [System model](https://backstage.io/docs/features/software-catalog/system-model)
- [Descriptor format](https://backstage.io/docs/features/software-catalog/descriptor-format) (kinds `Component`, `System`, `Resource`, `Group`, `User`, and the relations field)
- [Entity references](https://backstage.io/docs/features/software-catalog/references)
- [Well-known relations](https://backstage.io/docs/features/software-catalog/well-known-relations)
- [Life of an entity](https://backstage.io/docs/features/software-catalog/life-of-an-entity)

The dependencies come from the `*_ADDR` variables in the pinned release manifest of Online Boutique. The diagram comes from these two files, drawn by a script. See [docs/diagrams](../../../docs/diagrams/README.md).
