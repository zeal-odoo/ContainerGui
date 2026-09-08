import CryptoKit
import Foundation

struct AIModelFile: Equatable, Sendable {
    let path: String
    let size: Int64
    let sha256: String
}

struct AIModelCatalog: Sendable {
    let name: String
    let repository: String
    let revision: String
    let files: [AIModelFile]

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    var identity: String {
        let manifest = ([repository, revision] + files.map { "\($0.path)\t\($0.size)\t\($0.sha256)" }).joined(separator: "\n")
        return SHA256.hash(data: Data(manifest.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func validate() throws {
        guard repository == Self.qwen3.repository, revision == Self.qwen3.revision,
              !files.isEmpty, files.count <= 64, Set(files.map(\.path)).count == files.count else {
            throw AIModelStoreError.invalidManifest
        }
        var total: Int64 = 0
        for file in files {
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty, components.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy {
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
                }
            }), file.size > 0, file.size <= 700_000_000,
            file.sha256.count == 64, file.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw AIModelStoreError.invalidManifest
            }
            total += file.size
        }
        guard total <= 2_500_000_000 else { throw AIModelStoreError.invalidManifest }
    }

    func url(for file: AIModelFile) throws -> URL {
        try validate()
        guard files.contains(file), let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)") else {
            throw AIModelStoreError.invalidManifest
        }
        return url
    }

    static func permitsDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["huggingface.co", "cdn-lfs.huggingface.co", "cdn-lfs.hf.co",
                "cas-bridge.xethub.hf.co", "us.aws.cdn.hf.co"].contains(host)
    }

    // Pinned Hugging Face blob metadata; non-LFS SHA-256 values were computed from
    // this exact revision. Original Qwen3 weights: Apache-2.0; ANEMLL conversion card: MIT.
    // https://huggingface.co/anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5/tree/0977a61d00e39118aab5ed1e510f1d228df5eefd
    static let qwen3 = AIModelCatalog(
        name: "Qwen3-1.7B · ANEMLL Core ML (LUT6, 2048 context)",
        repository: "anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5",
        revision: "0977a61d00e39118aab5ed1e510f1d228df5eefd",
        files: [
            .init(path: "qwen_embeddings.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "2d9497e6cc728c81fc2c94ecd9b91224340d2a5676cb6451256cc4cb960dfdbb"),
            .init(path: "qwen_embeddings.mlmodelc/coremldata.bin", size: 560, sha256: "bbfa04acca7ab182c784460426c7f03eaea7c393d30635ff4e17369c992941d7"),
            .init(path: "qwen_embeddings.mlmodelc/metadata.json", size: 1989, sha256: "dd73b548992ff4db7919fd38c8e6637dda43732137ed85ca9d42cc801a4b9eb2"),
            .init(path: "qwen_embeddings.mlmodelc/model.mil", size: 2118, sha256: "565e9f6d87c203266543bb0a6a9c3ebec23ac2b753770e43c6c8e1c4ca0dd83b"),
            .init(path: "qwen_embeddings.mlmodelc/weights/weight.bin", size: 622329984, sha256: "80d4a53fa6ef9baa7f3411fbab47dfcc6434c4045af34d06fba90fbff676d8c8"),
            .init(path: "qwen_FFN_PF_lut6_chunk_01of02.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "62962552d3504795ae49877d64cb2becd53b3f4bea5fcc06ee7a3d5fb441f908"),
            .init(path: "qwen_FFN_PF_lut6_chunk_01of02.mlmodelc/coremldata.bin", size: 981, sha256: "3c9c963defecffbc19f052c1dbded9b4c8cbfb893b340a12c0721470e85f3be7"),
            .init(path: "qwen_FFN_PF_lut6_chunk_01of02.mlmodelc/metadata.json", size: 10194, sha256: "78e6c1f1a5bdaa5695e34756b6b3162119c4011d7d0112cee8ac02331827a6bb"),
            .init(path: "qwen_FFN_PF_lut6_chunk_01of02.mlmodelc/model.mil", size: 1090707, sha256: "cfee60d7e864a9d0902688ef1c653889e0dca92b8041c54ea5a7f577e030710f"),
            .init(path: "qwen_FFN_PF_lut6_chunk_01of02.mlmodelc/weights/weight.bin", size: 539892672, sha256: "748e49e0e7c213647880c6aa68a14e086f9181c12f03ad731b8e8129dcd22e82"),
            .init(path: "qwen_FFN_PF_lut6_chunk_02of02.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "3907a4ea0e95a988c85a6ff012d1b4ee07f90a4eed373fe270c2128f85dc3bfc"),
            .init(path: "qwen_FFN_PF_lut6_chunk_02of02.mlmodelc/coremldata.bin", size: 981, sha256: "fc4805bba9e1e75b6e6370fab189ddf3e22a9c790bef9005a8f262bb12f95a5a"),
            .init(path: "qwen_FFN_PF_lut6_chunk_02of02.mlmodelc/metadata.json", size: 10192, sha256: "4bbefe63d92d17a6a536b64a9a5f241076052351e7b753f24b6d18be1155f410"),
            .init(path: "qwen_FFN_PF_lut6_chunk_02of02.mlmodelc/model.mil", size: 1093914, sha256: "96db06dacd7b3c704742c56328af0b5a9c4f1fe11a11dca99387264cf4c71e5c"),
            .init(path: "qwen_FFN_PF_lut6_chunk_02of02.mlmodelc/weights/weight.bin", size: 539896832, sha256: "579bcd695adec21d98a8c74f6bf5a1e1484884771be69b64691164fcabd4cb4e"),
            .init(path: "qwen_lm_head_lut6.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "eef9d9f082e484b3e2a8f9b182cba9be44907d48c269feb7765c8b4ea78a3fa8"),
            .init(path: "qwen_lm_head_lut6.mlmodelc/coremldata.bin", size: 957, sha256: "6a1ad7b1d258f78ae38a5bc656708e77e7bd904985a69f7c650b595db5db45f6"),
            .init(path: "qwen_lm_head_lut6.mlmodelc/metadata.json", size: 6621, sha256: "9770a666d7534b63442e3739aa72687b7ddf6ec7efff81860656f8111657954b"),
            .init(path: "qwen_lm_head_lut6.mlmodelc/model.mil", size: 30457, sha256: "4de9d3f7408a7a8ecb9ece602183fc4bd74b6e303cb1e5ee613b203e68e8fcef"),
            .init(path: "qwen_lm_head_lut6.mlmodelc/weights/weight.bin", size: 238237760, sha256: "fd461430cdafa077d5e64249f056f7fcaa962f7531378f065b572bd24debc42f"),
            .init(path: "tokenizer.json", size: 11422654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
            .init(path: "tokenizer_config.json", size: 9732, sha256: "d5d09f07b48c3086c508b30d1c9114bd1189145b74e982a265350c923acd8101")
        ]
    )
}
