# A "buggy release" of podinfo: pods start, probes pass, Argo CD says Healthy,
# but every application request returns HTTP 500.
# It uses podinfo's built-in fault injection, which leaves /healthz, /readyz and
# /metrics working, exactly like a real bug that health checks don't catch.
ARG BASE
FROM ${BASE}
USER root
RUN mv /home/app/podinfo /home/app/podinfo-bin
COPY podinfo-wrapper.sh /home/app/podinfo
RUN chmod 755 /home/app/podinfo
USER app
