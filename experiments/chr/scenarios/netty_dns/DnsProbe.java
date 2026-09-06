import io.vertx.core.Vertx;
import io.vertx.core.VertxOptions;
import io.vertx.core.impl.VertxInternal;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public class DnsProbe {
    public static void main(String[] args) throws Exception {
        String server = args[0];
        int rounds = args.length > 1 ? Integer.parseInt(args[1]) : 4;
        int burst = args.length > 2 ? Integer.parseInt(args[2]) : 12;
        VertxOptions options = new VertxOptions();
        options.getAddressResolverOptions().setServers(List.of(server)).setMaxQueries(4);
        VertxInternal vertx = (VertxInternal) Vertx.vertx(options);
        try {
            for (int round = 0; round < rounds; round++) {
                AtomicInteger ok = new AtomicInteger();
                AtomicInteger failed = new AtomicInteger();
                AtomicReference<Throwable> error = new AtomicReference<>();
                CountDownLatch done = new CountDownLatch(burst);
                for (int i = 0; i < burst; i++) {
                    vertx.resolveAddress("s3.eu-west-1.amazonaws.com", result -> {
                        if (result.succeeded()) ok.incrementAndGet();
                        else {
                            failed.incrementAndGet();
                            error.compareAndSet(null, result.cause());
                        }
                        done.countDown();
                    });
                }
                if (!done.await(30, TimeUnit.SECONDS)) throw new IllegalStateException("lookup timeout");
                System.out.printf("server=%s round=%d ok=%d failed=%d error=%s%n", server, round, ok.get(), failed.get(), error.get());
                if (round + 1 < rounds) Thread.sleep(6000);
            }
        } finally {
            vertx.close().toCompletionStage().toCompletableFuture().get(10, TimeUnit.SECONDS);
        }
    }
}
