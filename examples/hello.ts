print("Hello from Tinyscript!")
print("It works :3")

let x = 42
let name = "Tinyscript"

if x > 10 {
  print("x is big:", x)
} else {
  print("x is small")
}

// Loop test
let i = 0
while i < 5 {
  print("Loop:", i)
  i = i + 1
}

// Function test
fun add(a, b) {
  return a + b
}

let result = add(10, 20)
print("10 + 20 =", result)

// Array test
let arr = [1, 2, 3, 4, 5]
print("Array length:", len(arr))
print("First element:", arr[0])

// Object test
let obj = { name: "tinyscript", version: 0.1 }
print("Object name:", obj["name"])

// Range test
for i in 0..3 {
  print("Range:", i)
}

print("All tests passed! uwu")
