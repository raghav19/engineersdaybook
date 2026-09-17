# using policy-as-code(PaC) to enforce security guardrails

today, cloud-native is now an extremely large [landscape](https://landscape.cncf.io/) to choose from providing us with plethora of options to pick and choose that fits our usecases with the right trade-offs that we can deal with at scale. in this ecosystem, kubernetes is a vendor-neutral platform which needs strong security guardrails of its own

security, being a layered approach needs guardrails, checks, audits and governance at multiple layers and enabling this at scale becomes a challenge unless we use some standards that help with the same at scale -> policy as code(PaC)

however, at scale when there are multiple features and so many services to be deployed, it becomes pretty hard to maintain consistency around guardrails and labelling leading to governance issues and this gets multiplied manifold when you are talking about governance across multiple clusters and multi cloud. to manage this at scale, came [PaC](https://www.cncf.io/blog/2025/07/29/introduction-to-policy-as-code/) that allows to standardize, audit and govern the workloads at scale

in this write-up, i will show how admission control plays a pivotal role in providing strong security guardrails and a working code example of enabling the policy with an admission controller [kyverno]()

## admission control in k8s

![Admission Controller Phases](https://kubernetes.io/images/blog/2019-03-21-a-guide-to-kubernetes-admission-controllers/admission-controller-phases.png)

​							       *source: [kubernetes blog](https://kubernetes.io/blog/2019/03/21/a-guide-to-kubernetes-admission-controllers/)*

admission controller can be considered as a gatekeeper that intercept the authenticated API request and run a mutation or validation on top the request to modify or deny the request entirely respectively

a comprehensive list for the built-in admission controllers in kubernetes are available here - [admission Control in kubernetes](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#what-does-each-admission-controller-do)

some great usecases of admission controls are:

- `security` - helps to mandate/enforce a reasonable security baseline across namespace/cluster
- `governance` - helps to mandate/enforce adherence to certain practices like having pod labels and other settings and even mutate as needed
- `config management` - helps to validate configuration issues for incoming objects hitting the cluster

further ahead we will see a practical application of security policy enforcement with admission control 

## what's kyverno?

[kyverno](https://kyverno.io/docs/introduction/#about-kyverno) is a unified policy engine. its a controller that processes the rules that we will define as custom resource objects. this admission controller is outside of the default controllers that comes built-in with kubernetes. it allows us to automate security, compliance and best practices through validation and mutation webhooks. it has lot of cool features out of the box that simplifies managing policies at scale, to name a few

- works with `YAML` or `CEL` syntax policies
- declarative management of polices -> `gitops` friendly
- policy reporting for audits and dashboards
- can do policy exceptions
- tooling available to test policies E2E

## security policies with pod security standards

when a pod is admitted into the cluster, its crucial to validate some key settings that generally are easy to miss or are a part of larger template which should be available as a golden set to use from. enforcing and enabling this should not be in the hands of a developer but must be set into the system to work for all by default

one such fundamental guardrail in kubernetes is the [pod security standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) which provides this exact set as different profiles to work with, however enabling, auditing this is part of an external engine which is where `kyverno` shines

pod security standards, provide 3 profiles to work with:

- privileged - unrestricted with privilege escalation -> *no guardrails*
- baseline - minimally restrictive policies to prevent known privilege escalations -> *enables ease of adoption*
- restricted - heavily restricted policies for Pod hardening -> *more focused towards security critical apps*

the specific profile level policies can be understood further [here](https://kubernetes.io/docs/concepts/security/pod-security-standards/#profile-details)

## getting them to work

<TBA> - write about working with kyverno and kind

## show me the code

<TBA>



## references

- [A Guide to Kubernetes Admission Controllers | Kubernetes](https://kubernetes.io/blog/2019/03/21/a-guide-to-kubernetes-admission-controllers/)
- [Pod Security Standards | Kubernetes](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kyverno](https://kyverno.io/)