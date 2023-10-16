import AWSLambdaRuntime

struct Input: Codable {
    enum Operation: String, Codable {
        case add
        case sub
        case mul
        case div
    }
    let a: Double
    let b: Double
    let op: Operation
}

struct Output: Codable {
    let result: Double
}

@main
struct Calc: SimpleLambdaHandler {
    func handle(_ input: Input, context: LambdaContext) async throws -> Output {
        let result: Double

        switch input.op {
        case .add:
            result = input.a + input.b
        case .sub:
            result = input.a - input.b
        case .mul:
            result = input.a * input.b
        case .div:
            result = input.a / input.b
        }

        return Output(result: result)
    }
}
