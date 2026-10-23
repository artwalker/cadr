(
(:module nil "AGFzbQEAAAABEQRgAX8Bf2AAAGAAAX9gAAF+AwgHAAABAgMBAQeXAQcQc2VsZWN0LXRyYXAtbGVmdAAAEXNlbGVjdC10cmFwLXJpZ2h0AAEQc2VsZWN0LXVucmVhY2hlZAACGXNlbGVjdF91bnJlYWNoZWRfcmVzdWx0XzEAAxlzZWxlY3RfdW5yZWFjaGVkX3Jlc3VsdF8yAAQPdW5yZWFjaGFibGUtbnVtAAUPdW5yZWFjaGFibGUtcmVmAAYKUgcIAABBACAAGwsIAEEAACAAGwsgAAAbAEEAGwBBAEEAGwBBAEEAQQAbAEMAAAAAQQAbAAsFAAAbagsJAABCAEEAG3wLBgAAG0UaCwYAABvRGgs=")
(:assert-trap (:invoke nil "select-trap-left" (:i32 1)) "unreachable")
(:assert-trap (:invoke nil "select-trap-left" (:i32 0)) "unreachable")
(:assert-trap (:invoke nil "select-trap-right" (:i32 1)) "unreachable")
(:assert-trap (:invoke nil "select-trap-right" (:i32 0)) "unreachable")
(:module nil "AGFzbQEAAAABBAFgAAADAgEABw8BC21lZXQtYm90dG9tAAAKHQEbAAJ8An0AQQEOAgABAQsaRAAAAAAAAAAACxoL")
(:assert-trap (:invoke nil "meet-bottom" ) "unreachable")
)
