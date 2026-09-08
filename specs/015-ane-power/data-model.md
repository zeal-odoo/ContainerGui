# Data model

ANE power snapshot: `state` = sampling/ready/unavailable; `watts`: finite nonnegative number or null; `observedAt`: ISO8601 date; `sampleSeconds`: finite positive duration only for ready, otherwise null; `reason`: null or safe enum unsupported/read_failed/invalid_sample; `scope`: host; `estimated`: true; `utilizationPercent`: null; `utilizationState`: unavailable.

Internal read: bounded unique channel names, supported energy unit, nonnegative cumulative integer counter. Changed set/unit or regression invalidates pair. Service uses injectable monotonic clock, at most one raw read per second, baseline expires after 15 seconds. No negative/NaN/infinite published values, no disk persistence. Failures discard baseline and displayed value, later valid read returns sampling before ready.
