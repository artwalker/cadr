(
(:module nil "AGFzbQEAAAABBgFgAX8BfwMDAgAABw4CBGV2ZW4AAANvZGQAAQorAhQAIABBAEYEf0EBBSAAQQFrEAELCxQAIABBAEYEf0EABSAAQQFrEAALCw==")
(:assert-return (:invoke nil "even" (:i32 13)) ((:i32 0)))
(:assert-return (:invoke nil "even" (:i32 20)) ((:i32 1)))
(:assert-return (:invoke nil "odd" (:i32 13)) ((:i32 1)))
(:assert-return (:invoke nil "odd" (:i32 20)) ((:i32 0)))
)
