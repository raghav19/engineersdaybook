today we deploy large amount of microservices all the way till production with kubernetes as the cloud-native platform of choice for a plethora of workloads. however when it comes to providing developer feedback using the same platform for continuous integration(merging into the trunk) for microservices , it becomes a daunting task. as a general workflow, if a developer modifies just 2 microservices amongst 50+ interconnected microservices in a distributed system, some core workflow aspects that would constitute a developer feedback loop would be

- the system is able to build the affected services

- deploy it in a environment

- run tests & notify

in a distributed system, a pattern thats observed which does work at scale is that a dedicated environment is constantly drifted per PR and reset to baseline and this process running in a loop when there are so many PR's in the queue would lead to constant SLA breach or DevOOps in place of Devops leading to a large unfullfilled queue of pull requests thereby delaying feedback and considerably reducing developer velocity.

another pattern observed here is to replicate the microservice stack per namespace and deploy as a package in the namespace with affected and unaffected services in the mix to allow isolated testing, however this needs considerable lead time to deploy the entire chained namespace when dealing with multicloud and interacting beyond kubernetes thereby adding to considerable costs as well. imagine a large data pipeline with 100s of microservices, replication of data would need to be near real time and bring up a new environment every PR would me a never ending lead time for infrastructure setup and off the roof cloud costs

so, solving this needs a novel approach that extends beyond kubernetes however keeping the cloud-native patterns intact.

in this blog, we will see of how we can enable PR-review(preview) environments for microservices testing that can scale well in a large distributed system with [kubernetes](https://kubernetes.io/), [istio](https://istio.io/),[gateway-api](https://gateway-api.sigs.k8s.io/) and [fluxcd](https://fluxcd.io/) for stateless services

## the tech stack

in this entire work, we will use the following tech stack

| **area**               | **platform/tooling/apis** |
| ---------------------- | ------------------------- |
| orchestration          | kubernetes                |
| service-mesh           | istio                     |
| routing                | gateway-api               |
| gitops                 | fluxcd                    |
| continuous integration | github-actions            |

## what we want our system to do

given we know the problem, we also want to set some clear expectations out of the system we are building and these are

- the system should be able to deploy only the affected services in isolation -> a `pr-xxx` namespace

- it should be able to communicate to the baseline services which are unaffected -> in the `baseline` namespace

- the system should be able to deploy this entirely declaratively on a per commit basis -> `fluxcd`

- the system should be able to run tests and notify -> `fluxcd`

- the entire system should be observable -> `kiali`,`prometheus`, `grafana`

- the system should seamlessly integrate into existing CI workflow tools -> `github-actions`

## architecture

to-be-added

## the workflow

a typical developer experience in this architecture would look like as follows:

- a dev is working on a feature, raises a PR for a small chunk of specific changes around a specific functionality expecting review and merge to the trunk(main)

- the CI system would look for affected services and build the service/services and push to OCI registry

- the manifests for deployment along with advanced routing are rendered and pushed to OCI registry

- the reconcilliation manifest per PR is raised against a gitops repo

- the controller in the cluster looks for these changes and takes the system from actual to desired state

- tests are run and notification is sent with reports

## show me the code, dude!!!

to-be-added

## value

- reduced operational & cost overhead reducing duplication of environments

- faster feedback loop/increased developer velocity given each service is deployed in isolation per PR

- declartive system at play making it easy to manage

- no env drift as system is managed declartively with git as the source of truth(GitOps)

## tradeoffs

- routing can become complex with additional layers like [authorization-policies](https://istio.io/latest/docs/reference/config/security/authorization-policy/) in `istio`

## references

- this work wouldnt have been possible without a close collaboration with my friend and collegue nikos bregiannis

- additional references in this space are as below:

  - [uber-simplifying developer testing through slate](https://www.uber.com/en-DE/blog/simplifying-developer-testing-through-slate)

  - [signadot-sandbox testing the devex game changer for microservices](https://medium.com/@signadot/sandbox-testing-the-devex-game-changer-for-microservices-f23db11250f5)